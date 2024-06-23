//
//  Item.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
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
