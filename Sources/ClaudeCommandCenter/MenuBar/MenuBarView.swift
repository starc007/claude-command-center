import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Command Center")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            Divider().overlay(Theme.Colors.border)

            VStack(alignment: .leading, spacing: 8) {
                MenuRow(icon: "square.stack.3d.up", title: "Sessions") {
                    openWindow(id: "main")
                }
                MenuRow(icon: "network", title: "Ports") {
                    openWindow(id: "main")
                }
                MenuRow(icon: "chart.line.uptrend.xyaxis", title: "Cost") {
                    openWindow(id: "main")
                }
                MenuRow(icon: "cube.transparent", title: "MCP Servers") {
                    openWindow(id: "main")
                }
            }

            Divider().overlay(Theme.Colors.border)

            HStack {
                Spacer()
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit").font(Theme.Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(Theme.Colors.accent)
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Animations.easeOut, value: hovering)
    }
}
