//
//  Item.swift
//  caloriecounter
//
//  Created by DJAviCC on 02/05/26.
//

import Foundation
import SwiftData

@Model
final class FoodEntry {
    var name: String
    var calories: Int
    var timestamp: Date

    init(name: String, calories: Int, timestamp: Date = Date()) {
        self.name = name
        self.calories = calories
        self.timestamp = timestamp
    }
}
