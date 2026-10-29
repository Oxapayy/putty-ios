import SwiftUI
import Logging

@main
struct PuTTYApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The SSH libraries use swift-log; route everything to nowhere.
        LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .onChange(of: scenePhase) { _, phase in app.scenePhaseChanged(phase) }
        }
    }
}
