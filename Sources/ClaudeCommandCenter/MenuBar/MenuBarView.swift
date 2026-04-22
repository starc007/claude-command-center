import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var checker = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Command Center")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("v\(AppVersion.current.description)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
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

            updateRow

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

    @ViewBuilder
    private var updateRow: some View {
        switch checker.state {
        case .available(let r):
            MenuRow(icon: "arrow.up.circle.fill", title: "Update to \(r.tagName)") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                checker.downloadAndStage()
            }
        case .ready:
            MenuRow(icon: "checkmark.circle.fill", title: "Install & relaunch") {
                checker.installStagedUpdate()
            }
        case .downloading(let p):
            HStack(spacing: 10) {
                ProgressView().controlSize(.mini)
                Text("Downloading update — \(Int(p * 100))%")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        default:
            MenuRow(icon: "arrow.clockwise", title: "Check for updates") {
                checker.checkNow()
            }
        }
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
