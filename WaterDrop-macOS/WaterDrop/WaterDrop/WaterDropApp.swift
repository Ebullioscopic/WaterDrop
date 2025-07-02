//
//  WaterDropApp.swift
//  WaterDrop
//
//  Created by admin23 on 28/05/25.
//

import SwiftUI
import SwiftData
import os.log

@main
struct WaterDropApp: App {
    private let logger = Logger(subsystem: "com.waterdrop.app", category: "WaterDropApp")
    @StateObject private var connectionManager = ConnectionManager()
    
    var sharedModelContainer: ModelContainer = {
        let logger = Logger(subsystem: "com.waterdrop.app", category: "ModelContainer")
        logger.info("🗄️ Creating ModelContainer...")
        
        let schema = Schema([
            TransferItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.info("✅ ModelContainer created successfully")
            return container
        } catch {
            logger.error("❌ Could not create ModelContainer: \(error)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        logger.info("🎬 WaterDropApp body rendering...")
        
        return WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    logger.info("📱 ContentView appeared")
                }
                .onDisappear {
                    logger.info("📱 ContentView disappeared")
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
