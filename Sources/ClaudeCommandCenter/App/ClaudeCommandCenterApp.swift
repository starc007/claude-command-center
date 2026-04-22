import SwiftUI

@main
struct ClaudeCommandCenterApp: App {
    init() {
        NotificationService.requestAuthorization()
        Task { @MainActor in
            IdleSessionWatcher.shared.start()
        }
    }

    var body: some Scene {
        Window("Claude Command Center", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Claude Command Center", systemImage: "sparkles") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
