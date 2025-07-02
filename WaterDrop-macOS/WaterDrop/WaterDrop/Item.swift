//
//  TransferItem.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

import Foundation
import SwiftData

@Model
final class TransferItem {
    var fileName: String
    var fileSize: Int64
    var transferDate: Date
    var isIncoming: Bool
    var checksum: String
    var filePath: String
    
    init(fileName: String, fileSize: Int64, isIncoming: Bool, checksum: String, filePath: String) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.transferDate = Date()
        self.isIncoming = isIncoming
        self.checksum = checksum
        self.filePath = filePath
    }
}

enum ConnectionState {
    case disconnected
    case discovering
    case connecting
    case connected
    case transferring
}

struct DiscoveredDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let identifier: String
    let rssi: Int
    let services: [String]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

struct FileTransfer: Identifiable {
    let id = UUID()
    let fileName: String
    let fileSize: Int64
    var progress: Double
    var bytesTransferred: Int64
    let isIncoming: Bool
    var status: TransferStatus
    let checksum: String
    
    enum TransferStatus {
        case pending
        case transferring
        case completed
        case failed
        case paused
    }
}
