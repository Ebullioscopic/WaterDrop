//
//  ContentView.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os.log

struct ContentView: View {
    private let logger = Logger(subsystem: "com.waterdrop.app", category: "ContentView")
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingFilePicker = false
    @State private var selectedFiles: [URL] = []
    @State private var showingTransferHistory = false
    @State private var animateConnection = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated background dots
            GeometryReader { geometry in
                ForEach(0..<50, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.02))
                        .frame(width: .random(in: 1...3))
                        .position(
                            x: .random(in: 0...geometry.size.width),
                            y: .random(in: 0...geometry.size.height)
                        )
                        .animation(
                            .easeInOut(duration: .random(in: 2...5))
                            .repeatForever(autoreverses: true),
                            value: animateConnection
                        )
                }
            }
            .onAppear { animateConnection.toggle() }
            
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    headerView
                    
                    // Connection Status
                    connectionStatusView
                    
                    // Device Discovery
                    deviceDiscoveryView
                    
                    // File Transfer Section
                    fileTransferView
                    
                    // Active Transfers
                    if !connectionManager.activeTransfers.isEmpty {
                        activeTransfersView
                    }
                    
                    // Transfer History
                    transferHistoryView
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            logger.info("📂 File picker result received")
            switch result {
            case .success(let urls):
                logger.info("✅ Files selected: \(urls.count) files")
                selectedFiles = urls
            case .failure(let error):
                logger.error("❌ File picker failed: \(error.localizedDescription)")
                connectionManager.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingTransferHistory) {
            TransferHistoryView()
                .environmentObject(connectionManager)
                .onAppear {
                    logger.info("📊 Showing transfer history sheet")
                }
        }
        .alert("Error", isPresented: .constant(connectionManager.errorMessage != nil)) {
            Button("OK") {
                logger.debug("❌ Error alert dismissed")
                connectionManager.errorMessage = nil
            }
        } message: {
            Text(connectionManager.errorMessage ?? "")
        }
        .onReceive(connectionManager.$connectionState) { newState in
            logger.info("🔄 Connection state changed to: \(String(describing: newState))")
        }
        .onReceive(connectionManager.$activeTransfers) { transfers in
            logger.debug("📁 Active transfers count: \(transfers.count)")
        }
        .onReceive(connectionManager.$discoveredDevices) { devices in
            logger.debug("📱 Discovered devices count: \(devices.count)")
        }
        .onAppear {
            logger.info("📱 ContentView appeared")
        }
        .onDisappear {
            logger.info("📱 ContentView disappeared")
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 15) {
            HStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.gray],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 8, height: 8)
                    .scaleEffect(connectionManager.connectionState == .connected ? 1.5 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: connectionManager.connectionState == .connected)
                
                Text("WaterDrop")
                    .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingTransferHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                .background(Circle().fill(Color.white.opacity(0.05)))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Text("Seamless peer-to-peer file transfer")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - Connection Status View
    private var connectionStatusView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 15) {
                statusIndicator
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(connectionStatusText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let device = connectionManager.connectedDevice {
                        Text("Connected to \(device.name)")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text(connectionSubtext)
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                if connectionManager.connectionState == .disconnected {
                    Button("Start Discovery") {
                        connectionManager.startDiscovery()
                    }
                    .buttonStyle(NothingButtonStyle(variant: .primary))
                } else if connectionManager.connectionState == .connected {
                    Button("Disconnect") {
                        connectionManager.disconnectFromDevice()
                    }
                    .buttonStyle(NothingButtonStyle(variant: .secondary))
                }
            }
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
        )
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 4)
                    .scaleEffect(connectionManager.connectionState == .discovering ? 2 : 1)
                    .opacity(connectionManager.connectionState == .discovering ? 0 : 1)
                    .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: connectionManager.connectionState == .discovering)
            )
    }
    
    private var statusColor: Color {
        switch connectionManager.connectionState {
        case .disconnected:
            return .red
        case .discovering:
            return .yellow
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .transferring:
            return .blue
        }
    }
    
    private var connectionStatusText: String {
        switch connectionManager.connectionState {
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Discovering devices..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .transferring:
            return "Transferring files..."
        }
    }
    
    private var connectionSubtext: String {
        switch connectionManager.connectionState {
        case .disconnected:
            return "Tap Start Discovery to find devices"
        case .discovering:
            return "Looking for nearby WaterDrop devices"
        case .connecting:
            return "Establishing secure connection"
        case .connected:
            return "Ready to transfer files"
        case .transferring:
            return "Files are being transferred"
        }
    }
    
    // MARK: - Device Discovery View
    private var deviceDiscoveryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Nearby Devices")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                if connectionManager.connectionState == .discovering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
            }
            
            if connectionManager.discoveredDevices.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No devices found")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Make sure both devices have WaterDrop open")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(connectionManager.discoveredDevices) { device in
                        DeviceRowView(device: device) {
                            connectionManager.connectToDevice(device)
                        }
                    }
                }
            }
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
        )
    }
    
    // MARK: - File Transfer View
    private var fileTransferView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("File Transfer")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
            
            VStack(spacing: 15) {
                Button("Select Files") {
                    showingFilePicker = true
                }
                .buttonStyle(NothingButtonStyle(variant: .primary))
                .disabled(connectionManager.connectionState != .connected)
                
                if !selectedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(selectedFiles.count) file(s) selected")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.7))
                        
                        ForEach(selectedFiles.prefix(3), id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.white.opacity(0.7))
                                Text(url.lastPathComponent)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        
                        if selectedFiles.count > 3 {
                            Text("and \(selectedFiles.count - 3) more...")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        Button("Send Files") {
                            connectionManager.transferFiles(selectedFiles)
                            selectedFiles.removeAll()
                        }
                        .buttonStyle(NothingButtonStyle(variant: .secondary))
                        .disabled(connectionManager.connectionState != .connected)
                    }
                    .padding(15)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
        )
    }
    
    // MARK: - Active Transfers View
    private var activeTransfersView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Active Transfers")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
            
            LazyVStack(spacing: 12) {
                ForEach(connectionManager.activeTransfers) { transfer in
                    TransferRowView(transfer: transfer)
                }
            }
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
        )
    }
    
    // MARK: - Transfer History View
    private var transferHistoryView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Recent")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("View All") {
                    showingTransferHistory = true
                }
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.white.opacity(0.7))
            }
            
            if connectionManager.transferHistory.isEmpty {
                Text("No transfers yet")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(connectionManager.transferHistory.prefix(3), id: \.fileName) { item in
                        HistoryRowView(item: item)
                    }
                }
            }
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
        )
    }
}

// MARK: - Custom Views
struct DeviceRowView: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                HStack(spacing: 10) {
                    Text("Signal: \(signalStrength)")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                    
                    if !device.services.isEmpty {
                        Text("• \(device.services.first ?? "")")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            Button("Connect") {
                onConnect()
            }
            .buttonStyle(NothingButtonStyle(variant: .minimal))
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.02))
                )
        )
    }
    
    private var deviceIcon: String {
        if device.services.contains("MultipeerConnectivity") {
            return "laptopcomputer"
        } else {
            return "iphone"
        }
    }
    
    private var signalStrength: String {
        let rssi = device.rssi
        if rssi >= -50 {
            return "Strong"
        } else if rssi >= -70 {
            return "Good"
        } else {
            return "Weak"
        }
    }
}

struct TransferRowView: View {
    let transfer: FileTransfer
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: transfer.isIncoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(transfer.isIncoming ? .green : .blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(formatFileSize(transfer.fileSize))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)
                    
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            ProgressView(value: transfer.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: transfer.isIncoming ? .green : .blue))
                .scaleEffect(y: 0.5)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var statusText: String {
        switch transfer.status {
        case .pending:
            return "Pending"
        case .transferring:
            return "Transferring"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .paused:
            return "Paused"
        }
    }
    
    private var statusColor: Color {
        switch transfer.status {
        case .pending:
            return .yellow
        case .transferring:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused:
            return .orange
        }
    }
}

struct HistoryRowView: View {
    let item: TransferItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isIncoming ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundColor(item.isIncoming ? .green : .blue)
                .opacity(0.7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(formatFileSize(item.fileSize))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("•")
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(formatDate(item.transferDate))
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            Button(action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.filePath))
            }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
    }
}

struct TransferHistoryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Transfer History")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(NothingButtonStyle(variant: .minimal))
            }
            
            if connectionManager.transferHistory.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No transfer history")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Files you send and receive will appear here")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(connectionManager.transferHistory, id: \.fileName) { item in
                            HistoryRowView(item: item)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                    }
                }
            }
        }
        .padding(30)
        .frame(width: 500, height: 400)
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.05, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Custom Button Style
struct NothingButtonStyle: ButtonStyle {
    enum Variant {
        case primary, secondary, minimal
    }
    
    let variant: Variant
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return .black
        case .secondary, .minimal:
            return .white
        }
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return Color.white.opacity(0.1)
        case .minimal:
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return Color.white.opacity(0.3)
        case .minimal:
            return Color.white.opacity(0.2)
        }
    }
}

// MARK: - Helper Functions
private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

#Preview {
    ContentView()
        .environmentObject(ConnectionManager())
}
