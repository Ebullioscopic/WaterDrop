//
//  MultipeerManager.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//


// MultipeerManager.swift
import Foundation
import MultipeerConnectivity
import Combine

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "p2p-transfer"
    private let myPeerID = MCPeerID(displayName: Host.current().name ?? "Unknown")
    
    private var mcSession: MCSession!
    private var mcAdvertiserAssistant: MCNearbyServiceAdvertiser!
    private var mcBrowser: MCNearbyServiceBrowser!
    
    @Published var availablePeers: [MCPeerID] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var connectionStatus = "Disconnected"
    @Published var activeTransfers: [String: Progress] = [:]
    @Published var receivedFiles: [URL] = []
    
    private let transferQueue = DispatchQueue(label: "transfer-queue", attributes: .concurrent)
    private let maxConcurrentTransfers = 4
    private var transferSemaphore: DispatchSemaphore
    
    var isConnected: Bool {
        return !connectedPeers.isEmpty
    }
    
    override init() {
        transferSemaphore = DispatchSemaphore(value: maxConcurrentTransfers)
        super.init()
        
        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }
    
    func startSession() {
        mcAdvertiserAssistant = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        mcAdvertiserAssistant.delegate = self
        mcAdvertiserAssistant.startAdvertisingPeer()
        
        mcBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        mcBrowser.delegate = self
        mcBrowser.startBrowsingForPeers()
        
        connectionStatus = "Searching for peers..."
    }
    
    func connectToPeer(_ peer: MCPeerID) {
        mcBrowser.invitePeer(peer, to: mcSession, withContext: nil, timeout: 10)
        connectionStatus = "Connecting..."
    }
    
    func sendFiles(_ urls: [URL]) {
        for url in urls {
            transferQueue.async { [weak self] in
                self?.transferSemaphore.wait()
                self?.sendFile(url)
                self?.transferSemaphore.signal()
            }
        }
    }
    
    private func sendFile(_ url: URL) {
        guard let peer = connectedPeers.first else { return }
        
        let fileName = url.lastPathComponent
        
        DispatchQueue.main.async {
            self.activeTransfers[fileName] = Progress(totalUnitCount: 0)
        }
        
        let progress = mcSession.sendResource(at: url, withName: fileName, toPeer: peer) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error sending file \(fileName): \(error)")
                }
                self.activeTransfers.removeValue(forKey: fileName)
            }
        }
        
        DispatchQueue.main.async {
            self.activeTransfers[fileName] = progress
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeers.append(peerID)
                self.connectionStatus = "Connected"
                
            case .connecting:
                self.connectionStatus = "Connecting..."
                
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.connectionStatus = "Disconnected"
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle text messages if needed
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async {
            self.activeTransfers[resourceName] = progress
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        DispatchQueue.main.async {
            self.activeTransfers.removeValue(forKey: resourceName)
            
            if let error = error {
                print("Error receiving file: \(error)")
                return
            }
            
            guard let localURL = localURL else { return }
            
            // Move file to permanent location
            // ✅ This is the correct syntax
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

            let destinationURL = documentsPath.appendingPathComponent(resourceName)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                self.receivedFiles.append(destinationURL)
            } catch {
                print("Error moving received file: \(error)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle streams if needed
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) {
                self.availablePeers.append(peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
        }
    }
}
