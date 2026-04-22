import SwiftUI

extension Theme {
    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold,    design: .default)
        static let title      = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline   = Font.system(size: 15, weight: .semibold, design: .default)
        static let body       = Font.system(size: 13, weight: .regular,  design: .default)
        static let caption    = Font.system(size: 11, weight: .regular,  design: .default)

        static let mono       = Font.system(size: 12, weight: .regular,  design: .monospaced)
        static let monoSmall  = Font.system(size: 11, weight: .regular,  design: .monospaced)

        static let sectionHeader = Font.system(size: 10, weight: .semibold, design: .default)
    }
}

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.sectionHeader)
            .textCase(.uppercase)
            .tracking(1.0)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

extension View {
    func sectionHeaderStyle() -> some View { modifier(SectionHeaderStyle()) }
}
