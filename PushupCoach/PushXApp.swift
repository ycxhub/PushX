import SwiftUI
import SwiftData
import os

@main
struct PushXApp: App {
    let modelContainer: ModelContainer

    init() {
        let logger = Logger(subsystem: "com.pushx", category: "AppStartup")
        do {
            modelContainer = try ModelContainer(for: PushupSession.self, PushupRepRecord.self)
        } catch {
            logger.error("ModelContainer init failed: \(error.localizedDescription) — falling back to in-memory store for safety")
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(
                    for: PushupSession.self, PushupRepRecord.self,
                    configurations: config
                )
            } catch {
                fatalError("Cannot create ModelContainer fallback: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
