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
            logger.error("ModelContainer init failed: \(error.localizedDescription) — resetting store")
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            do {
                modelContainer = try ModelContainer(
                    for: PushupSession.self, PushupRepRecord.self,
                    configurations: config
                )
            } catch {
                fatalError("Cannot create ModelContainer after reset: \(error)")
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
