//
//  ConnectionManager.swift
//  WaterDrop
//
//  Created by admin23 on 02/07/25.
//

import Foundation
import CoreBluetooth
import MultipeerConnectivity
import Combine
import CryptoKit
import Network

class ConnectionManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var transferHistory: [TransferItem] = []
    @Published var isBluetoothEnabled = false
    @Published var connectedDevice: DiscoveredDevice?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var mcSession: MCSession!
    private var mcAdvertiser: MCNearbyServiceAdvertiser!
    private var mcBrowser: MCNearbyServiceBrowser!
    
    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    private let characteristicUUID = CBUUID(string: "87654321-4321-4321-4321-CBA987654321")
    private let mcServiceType = "waterdrop-p2p"
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    private var transferQueue = DispatchQueue(label: "transfer.queue", qos: .userInitiated)
    private var concurrentTransferSemaphore = DispatchSemaphore(value: 4) // Max 4 concurrent transfers
    
    // WebRTC signaling
    private var signalingData: Data?
    private var peerSignalingData: Data?
    
    override init() {
        super.init()
        setupManagers()
    }
    
    // MARK: - Setup
    private func setupManagers() {
        // Bluetooth Central Manager
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Bluetooth Peripheral Manager
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        // Multipeer Connectivity
        let peerID = MCPeerID(displayName: Host.current().name ?? "WaterDrop Device")
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
        
        mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["deviceType": "WaterDrop"],
            serviceType: mcServiceType
        )
        mcAdvertiser.delegate = self
        
        mcBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: mcServiceType)
        mcBrowser.delegate = self
    }
    
    // MARK: - Public Methods
    func startDiscovery() {
        guard isBluetoothEnabled else {
            errorMessage = "Bluetooth is not enabled"
            return
        }
        
        connectionState = .discovering
        discoveredDevices.removeAll()
        
        // Start Bluetooth scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Start Multipeer Connectivity
        mcAdvertiser.startAdvertisingPeer()
        mcBrowser.startBrowsingForPeers()
        
        print("Started discovery...")
    }
    
    func stopDiscovery() {
        centralManager.stopScan()
        mcAdvertiser.stopAdvertisingPeer()
        mcBrowser.stopBrowsingForPeers()
        connectionState = .disconnected
        print("Stopped discovery")
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        connectionState = .connecting
        connectedDevice = device
        
        // Find the corresponding peripheral
        if let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == device.identifier }) {
            centralManager.connect(peripheral)
        }
    }
    
    func disconnectFromDevice() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        mcSession.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
    }
    
    func transferFiles(_ urls: [URL]) {
        guard connectionState == .connected else {
            errorMessage = "No device connected"
            return
        }
        
        for url in urls {
            transferQueue.async { [weak self] in
                self?.concurrentTransferSemaphore.wait()
                self?.transferFile(url)
                self?.concurrentTransferSemaphore.signal()
            }
        }
    }
    
    // MARK: - Private Methods
    private func transferFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            DispatchQueue.main.async {
                self.errorMessage = "Cannot access file: \(url.lastPathComponent)"
            }
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let fileSize = Int64(data.count)
            let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            
            let transfer = FileTransfer(
                fileName: fileName,
                fileSize: fileSize,
                progress: 0.0,
                bytesTransferred: 0,
                isIncoming: false,
                status: .pending,
                checksum: checksum
            )
            
            DispatchQueue.main.async {
                self.activeTransfers.append(transfer)
                self.connectionState = .transferring
            }
            
            // Send via MultipeerConnectivity
            let progress = mcSession.sendResource(at: url, withName: fileName, toPeer: mcSession.connectedPeers.first!) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = "Transfer failed: \(error.localizedDescription)"
                        if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                            self.activeTransfers[index].status = .failed
                        }
                    } else {
                        // Transfer completed
                        if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                            self.activeTransfers[index].status = .completed
                            self.activeTransfers[index].progress = 1.0
                            self.activeTransfers[index].bytesTransferred = fileSize
                        }
                        
                        // Add to history
                        let historyItem = TransferItem(
                            fileName: fileName,
                            fileSize: fileSize,
                            isIncoming: false,
                            checksum: checksum,
                            filePath: url.path
                        )
                        self.transferHistory.append(historyItem)
                    }
                    
                    // Check if all transfers are complete
                    if self.activeTransfers.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                        self.connectionState = .connected
                    }
                }
            }
            
            // Monitor progress
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                DispatchQueue.main.async {
                    if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.activeTransfers[index].progress = progress.fractionCompleted
                        self.activeTransfers[index].bytesTransferred = progress.completedUnitCount
                        
                        if progress.isFinished || self.activeTransfers[index].status != .transferring {
                            timer.invalidate()
                        }
                    }
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }
    
    private func generateWebRTCSignalingData() -> Data {
        // Simulate WebRTC SDP offer/answer exchange
        let signalingInfo = [
            "type": "offer",
            "sdp": "v=0\r\no=- \(UUID().uuidString) 2 IN IP4 127.0.0.1\r\n",
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        ]
        
        return try! JSONSerialization.data(withJSONObject: signalingInfo)
    }
}

// MARK: - CBCentralManagerDelegate
extension ConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isBluetoothEnabled = true
            print("Bluetooth is powered on")
        case .poweredOff:
            isBluetoothEnabled = false
            errorMessage = "Bluetooth is powered off"
        case .unauthorized:
            errorMessage = "Bluetooth access denied"
        case .unsupported:
            errorMessage = "Bluetooth not supported"
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let device = DiscoveredDevice(
            name: peripheral.name ?? "Unknown Device",
            identifier: peripheral.identifier.uuidString,
            rssi: RSSI.intValue,
            services: peripheral.services?.map { $0.uuid.uuidString } ?? []
        )
        
        if !discoveredDevices.contains(device) {
            discoveredDevices.append(device)
            discoveredPeripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        
        // Generate and exchange WebRTC signaling data
        signalingData = generateWebRTCSignalingData()
        
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        errorMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        connectionState = .disconnected
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        connectionState = .disconnected
        connectedDevice = nil
        
        if let error = error {
            errorMessage = "Disconnected with error: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension ConnectionManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                // Exchange WebRTC signaling data
                if let data = signalingData {
                    peripheral.writeValue(data, for: characteristic, type: .withResponse)
                }
                
                peripheral.setNotifyValue(true, for: characteristic)
                connectionState = .connected
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        // Handle received WebRTC signaling data
        peerSignalingData = data
        
        // Here you would typically establish WebRTC connection
        print("Received signaling data: \(data.count) bytes")
    }
}

// MARK: - CBPeripheralManagerDelegate
extension ConnectionManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            let service = CBMutableService(type: serviceUUID, primary: true)
            let characteristic = CBMutableCharacteristic(
                type: characteristicUUID,
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            service.characteristics = [characteristic]
            peripheralManager.add(service)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("Error adding service: \(error.localizedDescription)")
        } else {
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                CBAdvertisementDataLocalNameKey: "WaterDrop"
            ])
        }
    }
}

// MARK: - MCSessionDelegate
extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionState = .connected
                print("MC Session connected to: \(peerID.displayName)")
            case .connecting:
                self.connectionState = .connecting
            case .notConnected:
                if self.connectionState == .connected {
                    self.connectionState = .disconnected
                }
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle received data
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async {
            let transfer = FileTransfer(
                fileName: resourceName,
                fileSize: progress.totalUnitCount,
                progress: 0.0,
                bytesTransferred: 0,
                isIncoming: true,
                status: .transferring,
                checksum: ""
            )
            self.activeTransfers.append(transfer)
            self.connectionState = .transferring
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        DispatchQueue.main.async {
            if let index = self.activeTransfers.firstIndex(where: { $0.fileName == resourceName && $0.isIncoming }) {
                if let error = error {
                    self.activeTransfers[index].status = .failed
                    self.errorMessage = "Receive failed: \(error.localizedDescription)"
                } else if let localURL = localURL {
                    // Move file to Documents directory
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destinationURL = documentsPath.appendingPathComponent(resourceName)
                    
                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.moveItem(at: localURL, to: destinationURL)
                        
                        // Calculate checksum
                        let data = try Data(contentsOf: destinationURL)
                        let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                        
                        self.activeTransfers[index].status = .completed
                        self.activeTransfers[index].progress = 1.0
                        self.activeTransfers[index].bytesTransferred = Int64(data.count)
                        
                        // Add to history
                        let historyItem = TransferItem(
                            fileName: resourceName,
                            fileSize: Int64(data.count),
                            isIncoming: true,
                            checksum: checksum,
                            filePath: destinationURL.path
                        )
                        self.transferHistory.append(historyItem)
                        
                    } catch {
                        self.activeTransfers[index].status = .failed
                        self.errorMessage = "Failed to save file: \(error.localizedDescription)"
                    }
                }
                
                // Check if all transfers are complete
                if self.activeTransfers.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                    self.connectionState = .connected
                }
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle streams if needed
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            let device = DiscoveredDevice(
                name: peerID.displayName,
                identifier: peerID.displayName, // Using displayName as identifier for MC
                rssi: -50, // Simulated RSSI
                services: ["MultipeerConnectivity"]
            )
            
            if !self.discoveredDevices.contains(device) {
                self.discoveredDevices.append(device)
            }
        }
        
        // Auto-connect to the first discovered peer for demo purposes
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { $0.name == peerID.displayName }
        }
    }
}
