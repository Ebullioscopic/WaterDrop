//
//  BluetoothManager.swift
//  WaterDrop
//
//  Created by Copilot on 02/07/25.
//

import Foundation
import CoreBluetooth
import Combine
import os.log

/// Bluetooth Manager for macOS - Handles device discovery and WebRTC signaling
/// This matches the Android Bluetooth architecture for consistent behavior
class BluetoothManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.waterdrop.app", category: "BluetoothManager")
    
    // MARK: - Constants
    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
    private let characteristicUUID = CBUUID(string: "87654321-4321-4321-4321-CBA987654321")
    
    // MARK: - Published Properties
    @Published var isBluetoothEnabled = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectionState: BluetoothConnectionState = .disconnected
    @Published var connectedDevice: DiscoveredDevice?
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    // Signaling callback
    private var signalingCallback: ((WebRTCSignalingData) -> Void)?
    
    override init() {
        super.init()
        logger.info("📡 Initializing Bluetooth Manager")
        setupManagers()
    }
    
    // MARK: - Setup
    private func setupManagers() {
        logger.debug("🔧 Setting up Bluetooth managers")
        
        // Central Manager for scanning
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        
        // Peripheral Manager for advertising
        peripheralManager = CBPeripheralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    // MARK: - Public Methods
    func startDiscovery() {
        logger.info("🔍 Starting Bluetooth discovery")
        
        guard isBluetoothEnabled else {
            logger.error("❌ Bluetooth is not enabled")
            return
        }
        
        connectionState = .discovering
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        logger.debug("✅ Started scanning for peripherals")
    }
    
    func stopDiscovery() {
        logger.info("🛑 Stopping Bluetooth discovery")
        centralManager?.stopScan()
        connectionState = .disconnected
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        logger.info("🔗 Connecting to device: \(device.name)")
        
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == device.identifier }) else {
            logger.error("❌ Peripheral not found for device: \(device.identifier)")
            return
        }
        
        connectionState = .connecting
        connectedDevice = device
        centralManager?.connect(peripheral)
    }
    
    func disconnectFromDevice() {
        logger.info("🔌 Disconnecting from current device")
        
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        connectionState = .disconnected
        connectedDevice = nil
        connectedPeripheral = nil
        targetCharacteristic = nil
    }
    
    func setSignalingCallback(_ callback: @escaping (WebRTCSignalingData) -> Void) {
        logger.debug("📞 Setting signaling callback")
        signalingCallback = callback
    }
    
    func sendWebRTCSignaling(_ signalingData: WebRTCSignalingData) {
        logger.info("📡 Sending WebRTC signaling: \(signalingData.type.rawValue)")
        
        guard let peripheral = connectedPeripheral,
              let characteristic = targetCharacteristic else {
            logger.error("❌ Cannot send signaling - missing connection")
            return
        }
        
        guard let jsonString = signalingData.toJsonString(),
              let data = jsonString.data(using: .utf8) else {
            logger.error("❌ Cannot send signaling - failed to serialize data")
            return
        }
        
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        logger.debug("✅ Signaling data sent")
    }
    
    // MARK: - Private Methods
    private func handleReceivedSignalingData(_ data: Data) {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            logger.error("❌ Failed to parse signaling data - invalid UTF8")
            return
        }
        
        guard let signalingData = WebRTCSignalingData.fromJsonString(jsonString) else {
            logger.error("❌ Failed to parse signaling data - invalid JSON")
            return
        }
        
        logger.info("📨 Received WebRTC signaling: \(signalingData.type.rawValue)")
        signalingCallback?(signalingData)
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("📡 Bluetooth central state: \(central.state.rawValue)")
        
        DispatchQueue.main.async { [weak self] in
            switch central.state {
            case .poweredOn:
                self?.isBluetoothEnabled = true
                self?.logger.info("✅ Bluetooth powered on")
            case .poweredOff:
                self?.isBluetoothEnabled = false
                self?.logger.warning("⚠️ Bluetooth powered off")
            case .unauthorized:
                self?.isBluetoothEnabled = false
                self?.logger.error("❌ Bluetooth unauthorized")
            case .unsupported:
                self?.isBluetoothEnabled = false
                self?.logger.error("❌ Bluetooth unsupported")
            default:
                self?.isBluetoothEnabled = false
                self?.logger.debug("🔄 Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        logger.debug("🔍 Discovered peripheral: \(peripheral.name ?? "Unknown") (\(RSSI) dBm)")
        
        let device = DiscoveredDevice(
            name: peripheral.name ?? "Unknown Device",
            identifier: peripheral.identifier.uuidString,
            rssi: RSSI.intValue,
            services: peripheral.services?.map { $0.uuid.uuidString } ?? []
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !self.discoveredDevices.contains(device) {
                self.discoveredDevices.append(device)
                self.discoveredPeripherals.append(peripheral)
                self.logger.info("📱 Added device: \(device.name)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("🔗 Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .connected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
            self?.connectedDevice = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("🔌 Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        
        if let error = error {
            logger.error("❌ Disconnect error: \(error.localizedDescription)")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
            self?.connectedDevice = nil
            self?.connectedPeripheral = nil
            self?.targetCharacteristic = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            logger.error("❌ No services found")
            return
        }
        
        logger.debug("🔍 Discovered \(services.count) services")
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            logger.error("❌ No characteristics found")
            return
        }
        
        logger.debug("🔍 Discovered \(characteristics.count) characteristics")
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                targetCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                logger.info("✅ Setup complete - ready for WebRTC signaling")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else {
            logger.error("❌ No data received")
            return
        }
        
        logger.debug("📨 Received data: \(data.count) bytes")
        handleReceivedSignalingData(data)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("❌ Write failed: \(error.localizedDescription)")
        } else {
            logger.debug("✅ Data written successfully")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        logger.info("📡 Peripheral manager state: \(peripheral.state.rawValue)")
        
        if peripheral.state == .poweredOn {
            setupService()
        }
    }
    
    private func setupService() {
        logger.debug("🔧 Setting up Bluetooth service")
        
        let service = CBMutableService(type: serviceUUID, primary: true)
        let characteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        service.characteristics = [characteristic]
        peripheralManager?.add(service)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Failed to add service: \(error.localizedDescription)")
        } else {
            logger.info("✅ Service added successfully")
            
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                CBAdvertisementDataLocalNameKey: "WaterDrop"
            ])
            
            logger.info("📢 Started advertising")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        logger.debug("📨 Received write requests: \(requests.count)")
        
        for request in requests {
            if let data = request.value {
                handleReceivedSignalingData(data)
            }
            
            peripheral.respond(to: request, withResult: .success)
        }
    }
}

// MARK: - Supporting Enums
enum BluetoothConnectionState {
    case disconnected
    case discovering
    case connecting
    case connected
}
