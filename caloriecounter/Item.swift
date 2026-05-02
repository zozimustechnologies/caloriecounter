//
//  Item.swift
//  caloriecounter
//
//  Created by DJAviCC on 02/05/26.
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
