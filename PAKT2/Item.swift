//
//  Item.swift
//  PAKT2
//
//  Created by Grégoire Delacroix on 16/03/2026.
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
