//
//  Item.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
