//
//  ContentView.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

// ContentView.swift
import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var multipeerManager = MultipeerManager()
    @State private var selectedFiles: [URL] = []
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("P2P File Transfer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Connection Status
            VStack {
                Text("Status: \(multipeerManager.connectionStatus)")
                    .foregroundColor(multipeerManager.isConnected ? .green : .red)
                
                if multipeerManager.isConnected {
                    Text("Connected to: \(multipeerManager.connectedPeers.first?.displayName ?? "Unknown")")
                }
            }
            
            // Peer Discovery
            VStack {
                Text("Available Devices")
                    .font(.headline)
                
                if multipeerManager.availablePeers.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.gray)
                } else {
                    List(multipeerManager.availablePeers, id: \.self) { peer in
                        HStack {
                            Text(peer.displayName)
                            Spacer()
                            Button("Connect") {
                                multipeerManager.connectToPeer(peer)
                            }
                            .disabled(multipeerManager.isConnected)
                        }
                    }
                    .frame(height: 150)
                }
            }
            
            // File Selection and Transfer
            VStack {
                Button("Select Files to Send") {
                    showingFilePicker = true
                }
                .disabled(!multipeerManager.isConnected)
                
                if !selectedFiles.isEmpty {
                    Text("Selected \(selectedFiles.count) file(s)")
                    
                    Button("Send Files") {
                        multipeerManager.sendFiles(selectedFiles)
                    }
                    .disabled(!multipeerManager.isConnected)
                }
            }
            
            // Transfer Progress
            if !multipeerManager.activeTransfers.isEmpty {
                VStack {
                    Text("Active Transfers")
                        .font(.headline)
                    
                    ForEach(Array(multipeerManager.activeTransfers.keys), id: \.self) { fileName in
                        if let progress = multipeerManager.activeTransfers[fileName] {
                            VStack {
                                Text(fileName)
                                ProgressView(value: progress.fractionCompleted)
                                Text("\(Int(progress.fractionCompleted * 100))% - \(formatBytes(Int64(progress.completedUnitCount)))/\(formatBytes(Int64(progress.totalUnitCount)))")
                            }
                        }
                    }
                }
            }
            
            // Received Files
            if !multipeerManager.receivedFiles.isEmpty {
                VStack {
                    Text("Received Files")
                        .font(.headline)
                    
                    List(multipeerManager.receivedFiles, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button("Open") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                selectedFiles = urls
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
        .onAppear {
            multipeerManager.startSession()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview{
    ContentView()
}
