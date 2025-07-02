//
//  WaterDropApp.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

import SwiftUI
import SwiftData

@main
struct WaterDropApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TransferItem.self,
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
                .environmentObject(connectionManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
