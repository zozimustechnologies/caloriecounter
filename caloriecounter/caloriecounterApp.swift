//
//  caloriecounterApp.swift
//  caloriecounter
//
//  Created by DJAviCC on 02/05/26.
//

import SwiftUI
import SwiftData

@main
struct caloriecounterApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FoodEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
