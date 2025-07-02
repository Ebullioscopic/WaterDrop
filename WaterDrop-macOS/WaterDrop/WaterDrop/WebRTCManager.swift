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

/// WebRTC Manager for macOS - Simplified implementation for cross-platform compatibility
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
    
    // Signaling callbacks
    private var onLocalDescriptionReady: ((String) -> Void)?
    private var onIceCandidateReady: ((String) -> Void)?
    
    // MARK: - Public Publishers
    var receivedFiles: AnyPublisher<ReceivedFile, Never> {
        receivedFileSubject.eraseToAnyPublisher()
    }
    
    init() {
        logger.info("🌐 Initializing WebRTC Manager (Simplified)")
        
        // Simulate connected state after initialization for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.connectionState = .connected
            self?.dataChannelState = .open
        }
    }
    
    // MARK: - WebRTC Connection Methods
    func createOffer(onLocalDescription: @escaping (String) -> Void, onIceCandidate: @escaping (String) -> Void) {
        logger.info("🔄 Creating WebRTC offer (simulated)")
        
        onLocalDescriptionReady = onLocalDescription
        onIceCandidateReady = onIceCandidate
        
        // Simulate offer creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let simulatedOffer = "v=0\r\no=- 1234567890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
            onLocalDescription(simulatedOffer)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let simulatedCandidate = "candidate:1 1 UDP 2113667326 192.168.1.100 54400 typ host"
                onIceCandidate(simulatedCandidate)
                
                self?.connectionState = .connecting
            }
        }
    }
    
    func createAnswer(remoteOffer: String, onLocalDescription: @escaping (String) -> Void, onIceCandidate: @escaping (String) -> Void) {
        logger.info("🔄 Creating WebRTC answer (simulated)")
        
        onLocalDescriptionReady = onLocalDescription
        onIceCandidateReady = onIceCandidate
        
        // Simulate answer creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let simulatedAnswer = "v=0\r\no=- 9876543210 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
            onLocalDescription(simulatedAnswer)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let simulatedCandidate = "candidate:1 1 UDP 2113667326 192.168.1.101 54401 typ host"
                onIceCandidate(simulatedCandidate)
                
                self?.connectionState = .connecting
            }
        }
    }
    
    func setRemoteAnswer(_ remoteAnswer: String) {
        logger.info("🔄 Setting remote answer (simulated)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.connectionState = .connected
            self?.dataChannelState = .open
        }
    }
    
    func addIceCandidate(_ candidateString: String) {
        logger.debug("🧊 Adding ICE candidate (simulated): \(candidateString)")
        // Simulate ICE candidate processing
    }
    
    // MARK: - File Transfer Methods
    func sendFile(_ fileData: Data, fileName: String, onProgress: @escaping (Float) -> Unit = { _ in }) {
        logger.info("📤 Starting file transfer for \(fileName) (\(fileData.count) bytes)")
        
        guard dataChannelState == .open else {
            logger.error("❌ Data channel not open")
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
        
        // Simulate file transfer with progress
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for (index, chunk) in chunks.enumerated() {
                Thread.sleep(forTimeInterval: 0.05) // Simulate network delay
                
                transferState.sentChunks += 1
                let progress = Float(transferState.sentChunks) / Float(transferState.totalChunks)
                
                DispatchQueue.main.async {
                    onProgress(progress)
                    self.updateTransferProgress(transferId: transferId, progress: progress)
                }
                
                self.logger.debug("📦 Sent chunk \(index + 1)/\(chunks.count) for \(fileName)")
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.logger.info("✅ File transfer completed for \(fileName)")
                self?.pendingTransfers.removeValue(forKey: transferId)
                
                // Simulate file received on other end (for testing)
                self?.simulateFileReceived(fileName: fileName, fileData: fileData)
            }
        }
    }
    
    private func simulateFileReceived(fileName: String, fileData: Data) {
        // Simulate receiving the file on the other end (for testing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let receivedFile = ReceivedFile(
                fileName: fileName,
                data: fileData,
                fileSize: Int64(fileData.count)
            )
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
        connectionState = .closed
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

// MARK: - WebRTC Signaling Data Model
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
