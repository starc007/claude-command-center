import SwiftUI

/// Shared state between the main window and the menu-bar popover.
/// Holding the current sidebar selection here lets a menu-bar tap
/// deep-link into the right tab.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: SidebarSection = .sessions
}
