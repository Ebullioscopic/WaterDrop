//
//  ConnectionManager.swift
//  WaterDrop
//
//  Created by admin23 on 02/07/25.
//

import Foundation
import CoreBluetooth
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
    @Published var webRTCConnectionState: WebRTCConnectionState = .new
    
    // MARK: - Private Properties
    private let bluetoothManager = BluetoothManager()
    private let webRTCManager = WebRTCManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var transferQueue = DispatchQueue(label: "transfer.queue", qos: .userInitiated)
    private var concurrentTransferSemaphore = DispatchSemaphore(value: 4)
    
    // Progress tracking
    private var progressTimers: [UUID: Timer] = [:]
    
    override init() {
        super.init()
        logger.info("🚀 ConnectionManager initializing with WebRTC architecture...")
        setupBindings()
        setupWebRTCSignaling()
    }
    
    deinit {
        logger.info("🔄 ConnectionManager deinitializing...")
        cleanupTimers()
        webRTCManager.cleanup()
        cancellables.removeAll()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        logger.debug("🔗 Setting up property bindings")
        
        // Bind Bluetooth state
        bluetoothManager.$isBluetoothEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isBluetoothEnabled, on: self)
            .store(in: &cancellables)
        
        bluetoothManager.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .assign(to: \.discoveredDevices, on: self)
            .store(in: &cancellables)
        
        bluetoothManager.$connectedDevice
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectedDevice, on: self)
            .store(in: &cancellables)
        
        // Bind WebRTC state
        webRTCManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.webRTCConnectionState = state
                self?.updateConnectionState(from: state)
            }
            .store(in: &cancellables)
        
        // Handle received files
        webRTCManager.receivedFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receivedFile in
                self?.handleReceivedFile(receivedFile)
            }
            .store(in: &cancellables)
        
        logger.info("✅ Property bindings configured")
    }
    
    private func setupWebRTCSignaling() {
        logger.debug("📡 Setting up WebRTC signaling")
        
        bluetoothManager.setSignalingCallback { [weak self] signalingData in
            self?.handleWebRTCSignaling(signalingData)
        }
    }
    
    private func updateConnectionState(from webRTCState: WebRTCConnectionState) {
        switch webRTCState {
        case .connected:
            connectionState = .connected
        case .connecting:
            connectionState = .connecting
        case .disconnected, .failed, .closed:
            connectionState = .disconnected
        case .new:
            break // Keep current state
        }
    }
    
    // MARK: - Public Methods
    func startDiscovery() {
        logger.info("🔍 Starting device discovery")
        
        guard isBluetoothEnabled else {
            logger.error("❌ Bluetooth is not enabled")
            errorMessage = "Bluetooth is not enabled"
            return
        }
        
        connectionState = .discovering
        bluetoothManager.startDiscovery()
        logger.info("✅ Discovery started successfully")
    }
    
    func stopDiscovery() {
        logger.info("🛑 Stopping discovery")
        bluetoothManager.stopDiscovery()
        connectionState = .disconnected
        logger.info("✅ Discovery stopped")
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        logger.info("🔗 Connecting to device: \(device.name)")
        connectionState = .connecting
        bluetoothManager.connectToDevice(device)
    }
    
    func disconnectFromDevice() {
        logger.info("🔌 Disconnecting from device")
        bluetoothManager.disconnectFromDevice()
        webRTCManager.cleanup()
        connectionState = .disconnected
        cleanupTimers()
        logger.info("✅ Disconnected successfully")
    }
    
    func transferFiles(_ urls: [URL]) {
        logger.info("📁 Starting file transfer for \(urls.count) files")
        
        guard webRTCConnectionState == .connected else {
            logger.error("❌ WebRTC not connected for file transfer")
            errorMessage = "WebRTC connection not established"
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
    
    // MARK: - WebRTC Initiation
    func initiateWebRTCConnection() {
        logger.info("🌐 Initiating WebRTC connection")
        
        webRTCManager.createOffer { [weak self] localOffer in
            let offerSignaling = WebRTCSignalingData(
                type: .offer,
                data: localOffer,
                deviceId: ProcessInfo.processInfo.globallyUniqueString
            )
            self?.bluetoothManager.sendWebRTCSignaling(offerSignaling)
        } onIceCandidate: { [weak self] candidate in
            let candidateSignaling = WebRTCSignalingData(
                type: .iceCandidate,
                data: candidate,
                deviceId: ProcessInfo.processInfo.globallyUniqueString
            )
            self?.bluetoothManager.sendWebRTCSignaling(candidateSignaling)
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
            let checksum = calculateSHA256(data)
            
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
            
            // Send via WebRTC with proper type annotation
            webRTCManager.sendFile(data, fileName: fileName) { [weak self] (progress: Float) in
                DispatchQueue.main.async {
                    guard let self = self,
                          let index = self.activeTransfers.firstIndex(where: { $0.id == transfer.id }) else { return }
                    
                    self.activeTransfers[index].progress = Double(progress)
                    self.activeTransfers[index].bytesTransferred = Int64(Double(fileSize) * Double(progress))
                    self.activeTransfers[index].status = progress >= 1.0 ? .completed : .transferring
                    
                    if progress >= 1.0 {
                        // Add to transfer history
                        let historyItem = TransferItem(
                            fileName: fileName,
                            fileSize: fileSize,
                            isIncoming: false,
                            checksum: checksum,
                            filePath: url.path
                        )
                        self.transferHistory.append(historyItem)
                        
                        // Check if all transfers are done
                        if self.activeTransfers.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                            self.connectionState = .connected
                        }
                    }
                }
            }
            
        } catch {
            logger.error("❌ Failed to read file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleReceivedFile(_ receivedFile: ReceivedFile) {
        logger.info("📥 Handling received file: \(receivedFile.fileName)")
        
        // Save file to Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(receivedFile.fileName)
        
        do {
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Write the file
            try receivedFile.data.write(to: destinationURL)
            
            let checksum = calculateSHA256(receivedFile.data)
            
            // Add to transfer history
            let historyItem = TransferItem(
                fileName: receivedFile.fileName,
                fileSize: receivedFile.fileSize,
                isIncoming: true,
                checksum: checksum,
                filePath: destinationURL.path
            )
            transferHistory.append(historyItem)
            
            logger.info("✅ File saved successfully: \(destinationURL.path)")
            
        } catch {
            logger.error("❌ Failed to save received file: \(error.localizedDescription)")
            errorMessage = "Failed to save received file: \(error.localizedDescription)"
        }
    }
    
    private func handleWebRTCSignaling(_ signalingData: WebRTCSignalingData) {
        logger.info("📡 WEBRTC SIGNALING: Handling signaling type: \(signalingData.type.rawValue)")
        
        switch signalingData.type {
        case .offer:
            // Received an offer, create answer
            webRTCManager.createAnswer(remoteOffer: signalingData.data!) { [weak self] localAnswer in
                let answerSignaling = WebRTCSignalingData(
                    type: .answer,
                    data: localAnswer,
                    deviceId: ProcessInfo.processInfo.globallyUniqueString
                )
                self?.bluetoothManager.sendWebRTCSignaling(answerSignaling)
            } onIceCandidate: { [weak self] candidate in
                let candidateSignaling = WebRTCSignalingData(
                    type: .iceCandidate,
                    data: candidate,
                    deviceId: ProcessInfo.processInfo.globallyUniqueString
                )
                self?.bluetoothManager.sendWebRTCSignaling(candidateSignaling)
            }
            
        case .answer:
            // Received an answer, set it
            webRTCManager.setRemoteAnswer(signalingData.data!)
            
        case .iceCandidate:
            // Received ICE candidate, add it
            webRTCManager.addIceCandidate(signalingData.data!)
        }
    }
    
    private func calculateSHA256(_ data: Data) -> String {
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func cleanupTimers() {
        logger.debug("🧹 Cleaning up progress timers")
        for timer in progressTimers.values {
            timer.invalidate()
        }
        progressTimers.removeAll()
    }
}
