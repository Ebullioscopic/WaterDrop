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

protocol BluetoothManagerDelegate {
    func didDiscoverDevice(_ device: DiscoveredDevice)
    func didConnectToDevice(_ device: DiscoveredDevice)
    func didDisconnectFromDevice()
    func didReceiveConnectionRequest(from deviceName: String)
    func didReceiveData(_ data: Data)
    func didFailToConnect(error: Error)
}

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
    
    // MARK: - Delegate
    var delegate: BluetoothManagerDelegate?
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    // Service tracking
    private var waterDropService: CBMutableService?
    private var isServiceAdded = false
    
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
        logger.info("🔍 Starting Bluetooth discovery AND advertising (simultaneous mode)")
        
        guard isBluetoothEnabled else {
            logger.error("❌ Bluetooth is not enabled")
            return
        }
        
        connectionState = .discovering
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        
        // Start scanning for other devices
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        logger.info("✅ Started scanning for peripherals")
        
        // ALSO start advertising so other devices can find us
        // This is crucial - both devices need to be discoverable AND searching
        logger.info("📢 Checking peripheral manager state: \(self.peripheralManager?.state.rawValue ?? -1)")
        
        if let peripheralManager = peripheralManager {
            if peripheralManager.state == .poweredOn {
                // Ensure service is setup before advertising
                if !isServiceAdded {
                    logger.info("📢 Service not ready - setting up service first")
                    setupService()
                } else {
                    startAdvertising()
                    logger.info("📢 Started advertising immediately")
                }
            } else {
                logger.info("⏳ Peripheral manager not ready (state: \(peripheralManager.state.rawValue)), will start advertising when powered on")
            }
        } else {
            logger.error("❌ Peripheral manager is nil!")
        }
    }
    
    func stopDiscovery() {
        logger.info("🛑 Stopping Bluetooth discovery and advertising")
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        connectionState = .disconnected
    }
    
    // Debug method to manually restart advertising
    func forceRestartAdvertising() {
        logger.info("🔄 Force restarting advertising")
        peripheralManager?.stopAdvertising()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startAdvertising()
        }
    }
    
    // Debug method to verify service state
    func debugServiceState() {
        logger.info("🔍 DEBUG: Service state check")
        logger.info("🔍   isServiceAdded: \(self.isServiceAdded)")
        logger.info("🔍   waterDropServicself.e: \(self.waterDropService != nil ? "Present" : "Nil")")
        logger.info("🔍   peripheralManager state: \(self.peripheralManager?.state.rawValue ?? -1)")
        logger.info("🔍   peripheralManager isAdvertising: \(self.peripheralManager?.isAdvertising ?? false)")
        logger.info("🔍   connection state: \(String(describing: self.connectionState))")
        
        if let service = waterDropService {
            logger.info("🔍   service UUID: \(service.uuid.uuidString)")
            logger.info("🔍   service isPrimary: \(service.isPrimary)")
            if let characteristics = service.characteristics {
                logger.info("🔍   service has \(characteristics.count) characteristics")
                for char in characteristics {
                    logger.info("🔍     characteristic: \(char.uuid.uuidString)")
                }
            }
        }
    }
    
    private func startAdvertising() {
        logger.info("📢 Starting Bluetooth advertising to be discoverable")
        
        guard let peripheralManager = peripheralManager else {
            logger.error("❌ Peripheral manager is nil")
            return
        }
        
        guard peripheralManager.state == .poweredOn else {
            logger.warning("⚠️ Peripheral manager not ready for advertising - state: \(peripheralManager.state.rawValue)")
            return
        }
        
        // Stop any existing advertising first
        if peripheralManager.isAdvertising {
            logger.info("🛑 Stopping existing advertising")
            peripheralManager.stopAdvertising()
            
            // Wait a bit for the stop to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.continueStartAdvertising()
            }
        } else {
            continueStartAdvertising()
        }
    }
    
    private func continueStartAdvertising() {
        guard let peripheralManager = peripheralManager else {
            logger.error("❌ Peripheral manager is nil during continue advertising")
            return
        }
        
        // Verify our WaterDrop service is actually added
        logger.info("🔍 WaterDrop service availability check: \(self.isServiceAdded ? "✅ Present" : "❌ Missing")")
        
        if !isServiceAdded || waterDropService == nil {
            logger.error("❌ Cannot advertise - WaterDrop service not found in peripheral manager")
            logger.info("🔄 Re-adding WaterDrop service...")
            setupService()
            return
        }
        
        // Get device name from system
        let deviceName = ProcessInfo.processInfo.hostName
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: deviceName
            // Note: CBAdvertisementDataIsConnectable not allowed in macOS peripheral mode
        ]
        
        logger.info("📢 Starting advertisement with:")
        logger.info("📢   Service UUID: \(self.serviceUUID.uuidString)")
        logger.info("📢   Device name: \(deviceName)")
        logger.info("📢   Advertisement data: \(advertisementData)")
        
        peripheralManager.startAdvertising(advertisementData)
        logger.info("📢 Called startAdvertising() - waiting for callback")
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        logger.info("🔗 Connecting to device: \(device.name) - \(device.identifier)")
        
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == device.identifier }) else {
            logger.error("❌ Peripheral not found for device: \(device.identifier)")
            return
        }
        
        connectionState = .connecting
        connectedDevice = device
        
        // IMPORTANT: Stop scanning but KEEP advertising so Android can send signaling data
        logger.info("🛑 Stopping scanning but KEEPING advertising for incoming connections")
        centralManager?.stopScan()
        // DON'T stop advertising - Android needs to find us to send WebRTC signaling
        
        // Connect with timeout and proper options
        centralManager?.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        logger.info("🔗 Attempting connection to \(device.name)...")
    }
    
    func disconnectFromDevice() {
        logger.info("🔌 Disconnecting from current device")
        
        // Stop all Bluetooth activities
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        connectionState = .disconnected
        connectedDevice = nil
        connectedPeripheral = nil
        targetCharacteristic = nil
        
        // Reset service tracking
        isServiceAdded = false
        waterDropService = nil
        
        logger.info("✅ Disconnection complete")
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
        logger.info("🔍 Processing received Bluetooth signaling data (\(data.count) bytes)")
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            logger.error("❌ Failed to parse signaling data - invalid UTF8")
            logger.debug("❌ Raw data: \(data.map { String(format: "%02x", $0) }.joined())")
            return
        }
        
        logger.debug("🔍 JSON string: \(jsonString)")
        
        guard let signalingData = WebRTCSignalingData.fromJsonString(jsonString) else {
            logger.error("❌ Failed to parse signaling data - invalid JSON")
            logger.debug("❌ JSON content: \(jsonString)")
            return
        }
        
        logger.info("📨 BLUETOOTH SIGNALING: Received WebRTC signaling: \(signalingData.type.rawValue) from \(signalingData.deviceName ?? "Unknown")")
        logger.debug("📨 BLUETOOTH SIGNALING: Device ID: \(signalingData.deviceId)")
        
        // Call the signaling callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.signalingCallback?(signalingData)
        }
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
        let peripheralName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        logger.info("🔍 Discovered peripheral: \(peripheralName) (\(RSSI) dBm)")
        logger.debug("🔍 Advertisement data: \(advertisementData)")
        
        // Extract service UUIDs from advertisement
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceStrings = advertisedServices.map { $0.uuidString } + (peripheral.services?.map { $0.uuid.uuidString } ?? [])
        
        let device = DiscoveredDevice(
            name: peripheralName,
            identifier: peripheral.identifier.uuidString,
            rssi: RSSI.intValue,
            services: serviceStrings
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !self.discoveredDevices.contains(device) {
                self.discoveredDevices.append(device)
                self.discoveredPeripherals.append(peripheral)
                self.logger.info("📱 Added device: \(device.name) - \(device.identifier)")
                
                // IMPORTANT: Don't auto-connect when we find Android devices
                // Let Android connect to us as the peripheral instead
                if peripheralName.contains("WaterDrop") || peripheralName.contains("A059P") {
                    self.logger.info("🎯 Found WaterDrop Android device: \(peripheralName)")
                    self.logger.info("📱 Letting Android connect to us as peripheral - not auto-connecting")
                } else {
                    self.logger.debug("📱 Non-WaterDrop device discovered: \(peripheralName)")
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("🔗 Successfully connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = peripheral
        peripheral.delegate = self
        
        // Notify delegate about incoming connection request
        let deviceName = peripheral.name ?? "Unknown Device"
        delegate?.didReceiveConnectionRequest(from: deviceName)
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .connected
        }
        
        // Start service discovery
        logger.info("🔍 Starting service discovery...")
        peripheral.discoverServices([serviceUUID])
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
                
                // NOW we can stop advertising since we're ready to receive signaling
                logger.info("🛑 Stopping advertising - WebRTC signaling channel ready")
                peripheralManager?.stopAdvertising()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("❌ Characteristic read error: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            logger.error("❌ No data received from characteristic")
            return
        }
        
        logger.info("📨 Received data from Android device: \(data.count) bytes")
        logger.debug("📨 Raw data: \(data.map { String(format: "%02x", $0) }.joined())")
        
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
        logger.info("📡 Peripheral manager state changed to: \(peripheral.state.rawValue)")
        
        switch peripheral.state {
        case .poweredOn:
            logger.info("✅ Peripheral manager powered on - setting up WaterDrop service")
            // Add a small delay to ensure peripheral manager is fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupService()
            }
        case .poweredOff:
            logger.warning("⚠️ Peripheral manager powered off")
            isServiceAdded = false
            waterDropService = nil
        case .unauthorized:
            logger.error("❌ Peripheral manager unauthorized - check app permissions")
        case .unsupported:
            logger.error("❌ Peripheral manager unsupported on this device")
        case .resetting:
            logger.info("🔄 Peripheral manager resetting - will reinitialize")
            isServiceAdded = false
            waterDropService = nil
        case .unknown:
            logger.info("❓ Peripheral manager state unknown")
        @unknown default:
            logger.warning("⚠️ Unknown peripheral manager state: \(peripheral.state.rawValue)")
        }
    }
    
    private func setupService() {
        logger.info("🔧 Setting up Bluetooth GATT service")
        
        guard let peripheralManager = peripheralManager else {
            logger.error("❌ Peripheral manager is nil during service setup")
            return
        }
        
        guard peripheralManager.state == .poweredOn else {
            logger.error("❌ Cannot setup service - peripheral manager not powered on (state: \(peripheralManager.state.rawValue))")
            return
        }
        
        // Remove any existing services first and reset tracking
        peripheralManager.removeAllServices()
        isServiceAdded = false
        waterDropService = nil
        logger.info("🧹 Removed all existing services")
        
        // Wait a bit for cleanup to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            
            let service = CBMutableService(type: self.serviceUUID, primary: true)
            let characteristic = CBMutableCharacteristic(
                type: self.characteristicUUID,
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            
            service.characteristics = [characteristic]
            
            // Store reference to our service
            self.waterDropService = service
            
            self.logger.info("🔧 Creating WaterDrop service:")
            self.logger.info("🔧   Service UUID: \(self.serviceUUID.uuidString)")
            self.logger.info("🔧   Characteristic UUID: \(self.characteristicUUID.uuidString)")
            self.logger.info("🔧   Service is primary: \(service.isPrimary)")
            self.logger.info("🔧   Characteristic properties: \(characteristic.properties.rawValue)")
            self.logger.info("🔧   Characteristic permissions: \(characteristic.permissions.rawValue)")
            
            self.peripheralManager?.add(service)
            self.logger.info("🔧 Called add(service) - waiting for didAdd callback")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Failed to add WaterDrop service: \(error.localizedDescription)")
            logger.error("❌ Service UUID that failed: \(service.uuid.uuidString)")
            isServiceAdded = false
            return
        }
        
        // Mark service as successfully added
        isServiceAdded = true
        
        logger.info("✅ WaterDrop service added successfully!")
        logger.info("✅   Service UUID: \(service.uuid.uuidString)")
        logger.info("✅   Service is primary: \(service.isPrimary)")
        logger.info("✅   Expected UUID: \(self.serviceUUID.uuidString)")
        logger.info("✅   UUIDs match: \(service.uuid == self.serviceUUID)")
        
        // Verify characteristics were added
        if let characteristics = service.characteristics {
            logger.info("✅ Service has \(characteristics.count) characteristics:")
            for char in characteristics {
                logger.info("✅   Characteristic UUID: \(char.uuid.uuidString)")
                logger.info("✅   Properties: \(char.properties.rawValue)")
                logger.info("✅   Expected UUID: \(self.characteristicUUID.uuidString)")
                logger.info("✅   UUIDs match: \(char.uuid == self.characteristicUUID)")
            }
        } else {
            logger.error("❌ Service has no characteristics!")
        }
        
        // Now that service is confirmed added, start advertising if we're in discovery mode
        if connectionState == .discovering {
            logger.info("🔄 Service ready - starting advertising to be discoverable by Android")
            // Give a moment for the service to be fully registered in the system
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startAdvertising()
            }
        } else {
            logger.info("📝 Service ready but not in discovery mode")
            logger.info("🔄 However, starting advertising anyway to ensure service availability")
            // Always make the service available, even if not in discovery mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startAdvertising()
            }
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            logger.error("❌ Failed to start advertising: \(error.localizedDescription)")
        } else {
            logger.info("✅ Successfully started advertising - now discoverable by Android")
            logger.info("📢 Peripheral manager state: \(peripheral.state.rawValue)")
            logger.info("📢 Is advertising: \(peripheral.isAdvertising)")
            
            // Verify we're actually advertising by checking the state
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.logger.info("📊 Advertising status check - Is advertising: \(peripheral.isAdvertising)")
                self.logger.info("📊 Peripheral state: \(peripheral.state.rawValue)")
                
                if !peripheral.isAdvertising {
                    self.logger.warning("⚠️ Not advertising despite successful start - attempting restart")
                    self.startAdvertising()
                }
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        logger.info("📨 Received \(requests.count) write request(s) from Android device")
        
        for request in requests {
            if let data = request.value {
                logger.info("📨 Processing write request with \(data.count) bytes")
                logger.debug("📨 Write request data: \(data.map { String(format: "%02x", $0) }.joined())")
                handleReceivedSignalingData(data)
            } else {
                logger.warning("⚠️ Write request with no data")
            }
            
            peripheral.respond(to: request, withResult: .success)
        }
        
        logger.debug("✅ Responded to all write requests")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        logger.info("📱 Android device subscribed to characteristic: \(central.identifier)")
        logger.info("📱 Central maximum update value length: \(central.maximumUpdateValueLength)")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        logger.info("📱 Android device unsubscribed from characteristic: \(central.identifier)")
    }
    
    // MARK: - Connection Request Handling
    func acceptIncomingConnection() {
        logger.info("✅ User accepted incoming connection")
        // Connection is already established via Bluetooth, just notify
        delegate?.didConnectToDevice(connectedDevice ?? DiscoveredDevice(name: "Unknown Device", identifier: "unknown", rssi: 0, services: []))
    }
    
    func declineIncomingConnection() {
        logger.info("❌ User declined incoming connection")
        disconnectFromDevice()
    }
}

// MARK: - Supporting Enums
enum BluetoothConnectionState {
    case disconnected
    case discovering
    case connecting
    case connected
}
