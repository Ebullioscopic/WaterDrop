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
import os.log

class ConnectionManager: NSObject, ObservableObject {
    // MARK: - Logging
    private let logger = Logger(subsystem: "com.waterdrop.app", category: "ConnectionManager")
    
    // MARK: - Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var activeTransfers: [FileTransfer] = []
    @Published var transferHistory: [TransferItem] = []
    @Published var isBluetoothEnabled = false
    @Published var connectedDevice: DiscoveredDevice?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var mcSession: MCSession?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCNearbyServiceBrowser?
    
    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    private let characteristicUUID = CBUUID(string: "87654321-4321-4321-4321-CBA987654321")
    private let mcServiceType = "waterdrop-p2p"
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    private var transferQueue = DispatchQueue(label: "transfer.queue", qos: .userInitiated)
    private var concurrentTransferSemaphore = DispatchSemaphore(value: 4)
    
    // Progress tracking
    private var progressTimers: [UUID: Timer] = [:]
    
    // WebRTC signaling
    private var signalingData: Data?
    private var peerSignalingData: Data?
    
    override init() {
        super.init()
        logger.info("🚀 ConnectionManager initializing...")
        
        // Delay setup to avoid initialization crashes
        DispatchQueue.main.async { [weak self] in
            self?.setupManagers()
        }
    }
    
    deinit {
        logger.info("🔄 ConnectionManager deinitializing...")
        cleanupTimers()
        stopDiscovery()
    }
    
    // MARK: - Setup
    private func setupManagers() {
        logger.info("🔧 Setting up managers...")
        
        do {
            // Bluetooth Central Manager - with safe initialization
            centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
            
            // Bluetooth Peripheral Manager - with safe initialization
            peripheralManager = CBPeripheralManager(delegate: self, queue: DispatchQueue.main)
            
            // Multipeer Connectivity - with error handling
            let hostName = Host.current().name ?? "WaterDrop Device"
            logger.debug("Host name: \(hostName)")
            let peerID = MCPeerID(displayName: hostName)
            
            mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
            mcSession?.delegate = self
            
            mcAdvertiser = MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: ["deviceType": "WaterDrop"],
                serviceType: mcServiceType
            )
            mcAdvertiser?.delegate = self
            
            mcBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: mcServiceType)
            mcBrowser?.delegate = self
            
            logger.info("✅ All managers set up successfully")
        } catch {
            logger.error("❌ Failed to setup managers: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to initialize networking: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Public Methods
    func startDiscovery() {
        logger.info("🔍 Starting discovery...")
        
        guard isBluetoothEnabled else {
            logger.error("❌ Bluetooth is not enabled")
            errorMessage = "Bluetooth is not enabled"
            return
        }
        
        connectionState = .discovering
        discoveredDevices.removeAll()
        
        // Start Bluetooth scanning with safety checks
        if let centralManager = centralManager {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
            logger.debug("Started Bluetooth scanning")
        }
        
        // Start Multipeer Connectivity with safety checks
        mcAdvertiser?.startAdvertisingPeer()
        mcBrowser?.startBrowsingForPeers()
        
        logger.info("✅ Discovery started successfully")
    }
    
    func stopDiscovery() {
        logger.info("🛑 Stopping discovery...")
        centralManager?.stopScan()
        mcAdvertiser?.stopAdvertisingPeer()
        mcBrowser?.stopBrowsingForPeers()
        connectionState = .disconnected
        logger.info("✅ Discovery stopped")
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        logger.info("🔗 Connecting to device: \(device.name)")
        connectionState = .connecting
        connectedDevice = device
        
        if let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == device.identifier }) {
            logger.debug("Found peripheral, attempting connection...")
            centralManager?.connect(peripheral)
        } else {
            logger.error("❌ Peripheral not found for device: \(device.identifier)")
        }
    }
    
    func disconnectFromDevice() {
        logger.info("🔌 Disconnecting from device...")
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        mcSession?.disconnect()
        connectionState = .disconnected
        connectedDevice = nil
        cleanupTimers()
        logger.info("✅ Disconnected successfully")
    }
    
    func transferFiles(_ urls: [URL]) {
        logger.info("📁 Starting file transfer for \(urls.count) files")
        
        guard connectionState == .connected else {
            logger.error("❌ No device connected for file transfer")
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
        logger.info("📤 Starting transfer for file: \(url.lastPathComponent)")
        
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("❌ Cannot access security scoped resource")
            DispatchQueue.main.async {
                self.errorMessage = "Cannot access file: \(url.lastPathComponent)"
            }
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
            logger.debug("🔒 Stopped accessing security scoped resource")
        }
        
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let fileSize = Int64(data.count)
            let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            
            logger.info("📊 File info - Name: \(fileName), Size: \(fileSize) bytes")
            
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
            
            // Send via MultipeerConnectivity with safety checks
            guard let mcSession = mcSession,
                  let firstPeer = mcSession.connectedPeers.first else {
                logger.error("❌ No connected peers found")
                DispatchQueue.main.async {
                    self.errorMessage = "No connected peers"
                }
                return
            }
            
            logger.debug("👥 Sending to peer: \(firstPeer.displayName)")
            
            let progress = mcSession.sendResource(at: url, withName: fileName, toPeer: firstPeer) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.error("❌ Transfer failed: \(error.localizedDescription)")
                        self.errorMessage = "Transfer failed: \(error.localizedDescription)"
                        if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                            self.activeTransfers[index].status = .failed
                        }
                    } else {
                        self.logger.info("✅ Transfer completed successfully")
                        if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                            self.activeTransfers[index].status = .completed
                            self.activeTransfers[index].progress = 1.0
                            self.activeTransfers[index].bytesTransferred = fileSize
                        }
                        
                        let historyItem = TransferItem(
                            fileName: fileName,
                            fileSize: fileSize,
                            isIncoming: false,
                            checksum: checksum,
                            filePath: url.path
                        )
                        self.transferHistory.append(historyItem)
                    }
                    
                    // Clean up timer
                    self.progressTimers[transfer.id]?.invalidate()
                    self.progressTimers.removeValue(forKey: transfer.id)
                    
                    if self.activeTransfers.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                        self.connectionState = .connected
                    }
                }
            }
            
            // Monitor progress with safe timer management
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    
                    if let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) {
                        self.activeTransfers[index].progress = progress?.fractionCompleted ?? 0.0
                        self.activeTransfers[index].bytesTransferred = progress?.completedUnitCount ?? 0
                        
                        if progress?.isFinished == true || self.activeTransfers[index].status != .transferring {
                            timer.invalidate()
                            self.progressTimers.removeValue(forKey: transfer.id)
                        }
                    } else {
                        timer.invalidate()
                        self.progressTimers.removeValue(forKey: transfer.id)
                    }
                }
                
                self.progressTimers[transfer.id] = timer
            }
            
        } catch {
            logger.error("❌ Failed to read file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }
    
    private func cleanupTimers() {
        logger.debug("🧹 Cleaning up progress timers")
        for timer in progressTimers.values {
            timer.invalidate()
        }
        progressTimers.removeAll()
    }
    
    private func generateWebRTCSignalingData() -> Data {
        logger.debug("🌐 Generating WebRTC signaling data...")
        let signalingInfo = [
            "type": "offer",
            "sdp": "v=0\r\no=- \(UUID().uuidString) 2 IN IP4 127.0.0.1\r\n",
            "deviceId": ProcessInfo.processInfo.globallyUniqueString
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: signalingInfo)
            logger.debug("✅ WebRTC signaling data generated")
            return data
        } catch {
            logger.error("❌ Failed to serialize signaling data: \(error)")
            return Data()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension ConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("📡 Bluetooth central manager state: \(central.state.rawValue)")
        
        DispatchQueue.main.async {
            switch central.state {
            case .poweredOn:
                self.isBluetoothEnabled = true
                self.logger.info("✅ Bluetooth is powered on")
            case .poweredOff:
                self.isBluetoothEnabled = false
                self.errorMessage = "Bluetooth is powered off"
                self.logger.error("❌ Bluetooth is powered off")
            case .unauthorized:
                self.errorMessage = "Bluetooth access denied"
                self.logger.error("❌ Bluetooth access denied")
            case .unsupported:
                self.errorMessage = "Bluetooth not supported"
                self.logger.error("❌ Bluetooth not supported")
            default:
                self.logger.debug("Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let device = DiscoveredDevice(
            name: peripheral.name ?? "Unknown Device",
            identifier: peripheral.identifier.uuidString,
            rssi: RSSI.intValue,
            services: peripheral.services?.map { $0.uuid.uuidString } ?? []
        )
        
        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(device) {
                self.discoveredDevices.append(device)
                self.discoveredPeripherals.append(peripheral)
                self.logger.info("📱 Discovered device: \(device.name)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("🔗 Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([self.serviceUUID])
            self.signalingData = self.generateWebRTCSignalingData()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.errorMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
            self.connectionState = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("🔌 Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.connectedPeripheral = nil
            self.connectionState = .disconnected
            self.connectedDevice = nil
            
            if let error = error {
                self.errorMessage = "Disconnected with error: \(error.localizedDescription)"
                self.logger.error("❌ Disconnect error: \(error.localizedDescription)")
            }
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
                if let data = signalingData {
                    peripheral.writeValue(data, for: characteristic, type: .withResponse)
                }
                
                peripheral.setNotifyValue(true, for: characteristic)
                
                DispatchQueue.main.async {
                    self.connectionState = .connected
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        peerSignalingData = data
        logger.info("📡 Received signaling data: \(data.count) bytes")
    }
}

// MARK: - CBPeripheralManagerDelegate
extension ConnectionManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        logger.info("📡 Peripheral manager state: \(peripheral.state.rawValue)")
        
        if peripheral.state == .poweredOn {
            let service = CBMutableService(type: serviceUUID, primary: true)
            let characteristic = CBMutableCharacteristic(
                type: characteristicUUID,
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            service.characteristics = [characteristic]
            peripheral.add(service)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Error adding service: \(error.localizedDescription)")
        } else {
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                CBAdvertisementDataLocalNameKey: "WaterDrop"
            ])
            logger.info("✅ Service added and advertising started")
        }
    }
}

// MARK: - MCSessionDelegate
extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        logger.info("👥 MC Session state changed: \(state.rawValue) for peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionState = .connected
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
        logger.debug("📦 Received data from peer: \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.info("📥 Started receiving: \(resourceName)")
        
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
        logger.info("📥 Finished receiving: \(resourceName)")
        
        DispatchQueue.main.async {
            if let index = self.activeTransfers.firstIndex(where: { $0.fileName == resourceName && $0.isIncoming }) {
                if let error = error {
                    self.activeTransfers[index].status = .failed
                    self.errorMessage = "Receive failed: \(error.localizedDescription)"
                    self.logger.error("❌ Receive failed: \(error.localizedDescription)")
                } else if let localURL = localURL {
                    // Move file to Documents directory
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destinationURL = documentsPath.appendingPathComponent(resourceName)
                    
                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.moveItem(at: localURL, to: destinationURL)
                        
                        let data = try Data(contentsOf: destinationURL)
                        let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                        
                        self.activeTransfers[index].status = .completed
                        self.activeTransfers[index].progress = 1.0
                        self.activeTransfers[index].bytesTransferred = Int64(data.count)
                        
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
                        self.logger.error("❌ Failed to save file: \(error.localizedDescription)")
                    }
                }
                
                if self.activeTransfers.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                    self.connectionState = .connected
                }
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        logger.debug("🌊 Received stream: \(streamName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("📨 Received invitation from: \(peerID.displayName)")
        invitationHandler(true, mcSession)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        logger.info("🔍 Found peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            let device = DiscoveredDevice(
                name: peerID.displayName,
                identifier: peerID.displayName,
                rssi: -50,
                services: ["MultipeerConnectivity"]
            )
            
            if !self.discoveredDevices.contains(device) {
                self.discoveredDevices.append(device)
            }
        }
        
        browser.invitePeer(peerID, to: mcSession!, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("📤 Lost peer: \(peerID.displayName)")
        
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { $0.name == peerID.displayName }
        }
    }
}
