import SwiftUI

enum Theme {}

/// Rich dark theme inspired by the shared mock — Linear / Arc-style restraint,
/// not high-contrast. Single branded accent (Claude-orange) kept for selection
/// and interactive highlights; green is the "running" hue.
extension Theme {
    enum Colors {
        // Window + surfaces
        static let background      = Color(white: 0.05)   // ≈ #0D0D0D
        static let surface         = Color(white: 0.09)   // card fill
        static let surfaceRaised   = Color(white: 0.13)   // hover / pressed
        static let border          = Color.white.opacity(0.06)
        static let borderStrong    = Color.white.opacity(0.10)

        // Text
        static let textPrimary     = Color.white
        static let textSecondary   = Color.white.opacity(0.55)
        static let textTertiary    = Color.white.opacity(0.35)

        // Branded accent
        static let accent          = Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x06 / 255.0)
        static let accentDim       = accent.opacity(0.15)

        // Status
        static let green           = Color(red: 0.30, green: 0.85, blue: 0.55)
        static let red             = Color(red: 0.95, green: 0.45, blue: 0.45)
        static let yellow          = Color(red: 0.98, green: 0.80, blue: 0.35)
    }
}
