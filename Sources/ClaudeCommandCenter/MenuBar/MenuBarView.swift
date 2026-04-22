import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Command Center")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            Divider().overlay(Theme.Colors.border)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SidebarSection.allCases) { section in
                    MenuRow(icon: section.icon, title: section.rawValue) {
                        select(section)
                    }
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
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func select(_ section: SidebarSection) {
        state.selection = section
        openWindow(id: "main")
        // Bring the app + window to the front even if the user was in another app.
        NSApp.activate(ignoringOtherApps: true)
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
                    .fill(hovering ? Theme.Colors.surfaceRaised : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Animations.easeOut, value: hovering)
    }
}
