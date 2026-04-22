import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
            )
    }
}

struct StatusDot: View {
    enum Status { case running, stopped, warning }
    var status: Status
    @State private var pulse = false

    private var color: Color {
        switch status {
        case .running: return Theme.Colors.green
        case .stopped: return Theme.Colors.red
        case .warning: return Theme.Colors.yellow
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 2.0 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
            )
            .onAppear {
                guard status == .running else { return }
                withAnimation(Theme.Animations.breath) { pulse = true }
            }
    }
}
