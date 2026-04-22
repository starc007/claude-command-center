import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.Colors.surface.opacity(0.6))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.borderStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
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
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
            )
            .onAppear {
                guard status == .running else { return }
                withAnimation(Theme.Animations.breath) { pulse = true }
            }
    }
}

#if DEBUG
#Preview("GlassCard") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusDot(status: .running)
                    Text("nodeops-console").font(Theme.Typography.headline)
                }
                Text("~/Desktop/work/nodeops")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: 320)
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
