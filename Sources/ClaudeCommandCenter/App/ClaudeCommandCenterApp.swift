import SwiftUI
import AppKit

@main
struct ClaudeCommandCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        .windowResizability(.contentSize)

        MenuBarExtra("Claude Command Center", systemImage: "sparkles") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force regular activation so the window receives clicks even when the
        // binary runs outside a signed `.app` bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
