import SwiftUI

enum Theme {}

/// Colors for the app. Native macOS everywhere except for a single Claude-orange
/// accent — we deliberately lean on system colors + materials so the window
/// chrome follows the user's appearance preference and feels Mac-native.
extension Theme {
    enum Colors {
        // Text — use primary / secondary so they flip correctly in light/dark.
        static let textPrimary   = Color.primary
        static let textSecondary = Color.secondary

        // Borders / separators driven by the system.
        static let border        = Color(nsColor: .separatorColor)
        static let borderStrong  = Color(nsColor: .separatorColor).opacity(1.0)

        // Surfaces — used when we need a subtle fill behind a material.
        static let surface       = Color(nsColor: .controlBackgroundColor)
        static let surfaceRaised = Color(nsColor: .windowBackgroundColor)

        // Our single branded accent.
        static let accent        = Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x06 / 255.0)
        static let accentDim     = accent.opacity(0.15)

        // Status colors — SwiftUI defaults pick up the native hue.
        static let green         = Color.green
        static let red           = Color.red
        static let yellow        = Color.yellow
    }
}
