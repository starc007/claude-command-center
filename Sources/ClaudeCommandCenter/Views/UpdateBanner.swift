import SwiftUI

/// Thin banner that appears at the top of the main window when an update is
/// available or being installed. Hidden for `.idle`, `.checking`, and
/// `.upToDate` unless an explicit check was triggered.
struct UpdateBanner: View {
    @ObservedObject private var checker = UpdateChecker.shared

    var body: some View {
        Group {
            switch checker.state {
            case .available(let release):
                availableBanner(release)
            case .downloading(let progress):
                downloadingBanner(progress: progress)
            case .ready(let release, _):
                readyBanner(release)
            case .installing:
                simpleBanner(text: "Installing update…", icon: "arrow.down.circle", color: Theme.Colors.accent, showSpinner: true)
            case .failed(let msg):
                failedBanner(message: msg)
            case .upToDate:
                EmptyView()
            case .idle, .checking:
                EmptyView()
            }
        }
    }

    private func availableBanner(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available — \(release.tagName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Running \(AppVersion.current.description). Release notes on GitHub.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { NSWorkspace.shared.open(release.releaseURL) } label: {
                Text("Notes").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }.buttonStyle(.plain)
            Button { checker.downloadAndStage() } label: {
                Text("Update").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Colors.accent))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(bannerBackground(tint: Theme.Colors.accent))
    }

    private func downloadingBanner(progress: Double) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.mini)
            Text("Downloading update — \(Int(progress * 100))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 120)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(bannerBackground(tint: Theme.Colors.accent))
    }

    private func readyBanner(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.green)
            Text("Update to \(release.tagName) is ready")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button { checker.installStagedUpdate() } label: {
                Text("Install and relaunch").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Colors.green))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(bannerBackground(tint: Theme.Colors.green))
    }

    private func failedBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update check failed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button { checker.checkNow() } label: {
                Text("Retry").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(bannerBackground(tint: Theme.Colors.yellow))
    }

    private func simpleBanner(text: String, icon: String, color: Color, showSpinner: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showSpinner { ProgressView().controlSize(.mini) }
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(bannerBackground(tint: color))
    }

    @ViewBuilder
    private func bannerBackground(tint: Color) -> some View {
        Rectangle()
            .fill(tint.opacity(0.08))
            .overlay(
                Rectangle().fill(Theme.Colors.border).frame(height: 1),
                alignment: .bottom
            )
    }
}
