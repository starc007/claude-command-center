import SwiftUI

/// Odometer-style counter that animates up from the previous value.
struct AnimatedCounter: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var font: Font
    var color: Color

    init(
        value: Double,
        font: Font = .system(size: 36, weight: .bold, design: .rounded),
        color: Color = Theme.Colors.textPrimary,
        format: @escaping (Double) -> String
    ) {
        self.value = value
        self.font = font
        self.color = color
        self.format = format
    }

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
    }
}

extension Double {
    /// Format as USD with automatically scaled precision.
    func asUSD() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = self < 10 ? 2 : (self < 100 ? 2 : 0)
        formatter.minimumFractionDigits = self < 10 ? 2 : (self < 100 ? 2 : 0)
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }

    func compactInt() -> String {
        let n = self
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", n / 1_000) }
        return String(Int(n))
    }
}
