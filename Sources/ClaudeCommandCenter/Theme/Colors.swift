import SwiftUI

enum Theme {}

extension Theme {
    enum Colors {
        static let background      = Color(hex: 0x0A0A0F)
        static let surface         = Color(hex: 0x13131A)
        static let surfaceRaised   = Color(hex: 0x1C1C26)
        static let border          = Color.white.opacity(0.08)
        static let borderStrong    = Color.white.opacity(0.15)

        static let textPrimary     = Color(hex: 0xF0F0F5)
        static let textSecondary   = Color(hex: 0x8B8B9E)

        static let accent          = Color(hex: 0xD97706)
        static let accentDim       = Color(hex: 0xD97706).opacity(0.15)

        static let green           = Color(hex: 0x34D399)
        static let red             = Color(hex: 0xF87171)
        static let yellow          = Color(hex: 0xFBBF24)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
