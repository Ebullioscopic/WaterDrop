//
//  WebRTCManager.swift
//  WaterDrop
//
//  Created by Copilot on 02/07/25.
//

import Foundation
import Network
import Combine
import CryptoKit
import os.log

/// WebRTC Manager for macOS - STRICT RULE: Only file transfers via WebRTC, signaling via Bluetooth
/// This matches the Android WebRTC architecture for consistent behavior
class WebRTCManager: ObservableObject {
    private let logger = Logger(subsystem: "com.waterdrop.app", category: "WebRTCManager")
    
    // MARK: - Constants
    private let dataChannelLabel = "waterdrop-files"
    private let chunkSize = 16384 // 16KB chunks for file transfer
    
    // MARK: - Published Properties
    @Published var connectionState: WebRTCConnectionState = .new
    @Published var dataChannelState: DataChannelState = .connecting
    @Published var transferProgress: [String: Float] = [:]
    
    // MARK: - Private Properties
    private var pendingTransfers: [String: FileTransferState] = [:]
    private var receivingFiles: [String: ReceivingFileState] = [:]
    private var receivedFileSubject = PassthroughSubject<ReceivedFile, Never>()
    private var dataChannelOpen = false
    
    // Signaling callbacks - these communicate with Bluetooth layer
    private var onLocalDescriptionReady: ((String) -> Void)?
    private var onIceCandidateReady: ((String) -> Void)?
    
    // MARK: - Public Publishers
    var receivedFiles: AnyPublisher<ReceivedFile, Never> {
        receivedFileSubject.eraseToAnyPublisher()
    }
    
    init() {
        logger.info("🌐 Initializing WebRTC Manager - FILES ONLY via WebRTC, signaling via Bluetooth")
        
        // Initialize in disconnected state - only connect when signaling completes
        connectionState = .new
        dataChannelState = .connecting
        dataChannelOpen = false
    }
    
    // MARK: - WebRTC Connection Methods
    func createOffer(onLocalDescription: @escaping (String) -> Void, onIceCandidate: @escaping (String) -> Void) {
        logger.info("🔄 Creating WebRTC offer - signaling will be sent via Bluetooth")
        
        onLocalDescriptionReady = onLocalDescription
        onIceCandidateReady = onIceCandidate
        
        // Simulate WebRTC offer creation (to be replaced with real WebRTC)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let simulatedOffer = "v=0\r\no=- 1234567890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
            self?.logger.debug("📤 Sending offer via Bluetooth signaling")
            onLocalDescription(simulatedOffer)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                let simulatedCandidate = "candidate:1 1 UDP 2113667326 192.168.1.100 54400 typ host"
                self?.logger.debug("📤 Sending ICE candidate via Bluetooth signaling")
                onIceCandidate(simulatedCandidate)
                
                self?.connectionState = .connecting
            }
        }
    }
    
    func createAnswer(remoteOffer: String, onLocalDescription: @escaping (String) -> Void, onIceCandidate: @escaping (String) -> Void) {
        logger.info("🔄 Creating WebRTC answer - signaling will be sent via Bluetooth")
        
        onLocalDescriptionReady = onLocalDescription
        onIceCandidateReady = onIceCandidate
        
        // Simulate WebRTC answer creation (to be replaced with real WebRTC)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let simulatedAnswer = "v=0\r\no=- 9876543210 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
            self?.logger.debug("📤 Sending answer via Bluetooth signaling")
            onLocalDescription(simulatedAnswer)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                let simulatedCandidate = "candidate:1 1 UDP 2113667326 192.168.1.101 54401 typ host"
                self?.logger.debug("📤 Sending ICE candidate via Bluetooth signaling")
                onIceCandidate(simulatedCandidate)
                
                self?.connectionState = .connecting
            }
        }
    }
    
    func setRemoteAnswer(_ remoteAnswer: String) {
        logger.info("� Received remote answer via Bluetooth signaling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.logger.info("🌐 WebRTC connection established - data channel opening")
            self?.connectionState = .connected
            self?.dataChannelState = .open
            self?.dataChannelOpen = true
        }
    }
    
    func addIceCandidate(_ candidateString: String) {
        logger.debug("📥 Received ICE candidate via Bluetooth signaling: \(candidateString)")
        // Simulate ICE candidate processing (to be replaced with real WebRTC)
    }
    
    // MARK: - File Transfer Methods
    func sendFile(_ fileData: Data, fileName: String, onProgress: @escaping (Float) -> Unit = { _ in }) {
        logger.info("📤 WEBRTC FILE TRANSFER: Starting transfer for \(fileName) (\(fileData.count) bytes)")
        
        guard dataChannelOpen && dataChannelState == .open else {
            logger.error("❌ WebRTC data channel not open - cannot send file via WebRTC")
            return
        }
        
        let transferId = generateTransferId()
        let chunks = fileData.chunked(into: chunkSize)
        
        var transferState = FileTransferState(
            fileName: fileName,
            totalChunks: chunks.count,
            sentChunks: 0,
            onProgress: onProgress
        )
        pendingTransfers[transferId] = transferState
        
        logger.info("🚀 Sending file via WebRTC DataChannel: \(fileName) (\(chunks.count) chunks)")
        
        // Simulate WebRTC DataChannel file transfer with progress
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for (index, chunk) in chunks.enumerated() {
                // Simulate WebRTC DataChannel send operation
                Thread.sleep(forTimeInterval: 0.05) // Simulate network transmission time
                
                transferState.sentChunks += 1
                let progress = Float(transferState.sentChunks) / Float(transferState.totalChunks)
                
                DispatchQueue.main.async {
                    onProgress(progress)
                    self.updateTransferProgress(transferId: transferId, progress: progress)
                }
                
                self.logger.debug("📦 WebRTC chunk sent \(index + 1)/\(chunks.count) for \(fileName)")
                
                // TODO: Replace with real WebRTC DataChannel.send()
                // For now, simulate by calling remote device's receiveFileChunk method
                self.simulateWebRTCDataChannelSend(chunk, fileName: fileName, chunkIndex: index, totalChunks: chunks.count)
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.logger.info("✅ WebRTC file transfer completed for \(fileName)")
                self?.pendingTransfers.removeValue(forKey: transferId)
            }
        }
    }
    
    private func simulateWebRTCDataChannelSend(_ chunkData: Data, fileName: String, chunkIndex: Int, totalChunks: Int) {
        // TODO: Replace this simulation with real WebRTC DataChannel.send()
        // This simulates the data being sent over WebRTC and received on the remote device
        logger.debug("🌐 Simulating WebRTC DataChannel send: chunk \(chunkIndex) for \(fileName)")
        
        // In real implementation, this would be:
        // dataChannel.sendData(RTCDataBuffer(data: chunkData, isBinary: true))
        // And the remote device would receive it via RTCDataChannelDelegate.dataChannel(_:didReceiveMessageWith:)
    }
    
    // This method simulates receiving file data via WebRTC DataChannel
    // In real implementation, this would be called by RTCDataChannelDelegate.dataChannel(_:didReceiveMessageWith:)
    func receiveFileFromRemote(fileName: String, fileData: Data) {
        logger.info("📥 WEBRTC FILE RECEIVED: \(fileName) from remote device (\(fileData.count) bytes)")
        
        guard dataChannelOpen else {
            logger.error("❌ WebRTC data channel not open - rejecting file reception")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let receivedFile = ReceivedFile(
                fileName: fileName,
                data: fileData,
                fileSize: Int64(fileData.count)
            )
            self?.logger.info("📥 Emitting received file via WebRTC: \(fileName)")
            self?.receivedFileSubject.send(receivedFile)
        }
    }
    
    private func generateTransferId() -> String {
        return String(Date().timeIntervalSince1970.rounded())
    }
    
    private func updateTransferProgress(transferId: String, progress: Float) {
        transferProgress[transferId] = progress
    }
    
    // MARK: - Cleanup
    func cleanup() {
        logger.info("🧹 Cleaning up WebRTC resources")
        pendingTransfers.removeAll()
        receivingFiles.removeAll()
        dataChannelOpen = false
        connectionState = .closed
        dataChannelState = .closed
    }
}

// MARK: - Supporting Enums and Structs
enum WebRTCConnectionState {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
}

enum DataChannelState {
    case connecting
    case open
    case closing
    case closed
}

// MARK: - Data Models
struct FileTransferState {
    let fileName: String
    let totalChunks: Int
    var sentChunks: Int
    let onProgress: (Float) -> Void
}

struct ReceivingFileState {
    let fileName: String
    let fileSize: Int64
    let totalChunks: Int
    var receivedChunks: [Int]
    let receivedData: Data
}

struct ReceivedFile {
    let fileName: String
    let data: Data
    let fileSize: Int64
}

// MARK: - WebRTC Signaling Data Model (Bluetooth signaling only - no file data)
struct WebRTCSignalingData: Codable {
    let type: SignalingType
    let data: String
    let deviceId: String
    
    enum SignalingType: String, Codable {
        case offer = "OFFER"
        case answer = "ANSWER"
        case iceCandidate = "ICE_CANDIDATE"
    }
    
    func toJsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func fromJsonString(_ jsonString: String) -> WebRTCSignalingData? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WebRTCSignalingData.self, from: data)
    }
}

// MARK: - Data Extension for Chunking
extension Data {
    func chunked(into size: Int) -> [Data] {
        return stride(from: 0, to: count, by: size).map {
            subdata(in: $0..<Swift.min($0 + size, count))
        }
    }
}

// MARK: - Unit Type Alias
typealias Unit = Void
