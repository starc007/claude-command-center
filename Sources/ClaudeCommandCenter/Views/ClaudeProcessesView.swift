import SwiftUI

@MainActor
final class ClaudeProcessesViewModel: ObservableObject {
    @Published var processes: [ClaudeProcess] = []
    @Published var isLoading = false

    func refresh() {
        isLoading = true
        Task { [weak self] in
            let fresh = await Task.detached(priority: .userInitiated) {
                ClaudeProcessScanner.scan()
            }.value
            self?.processes = fresh
            self?.isLoading = false
        }
    }

    func kill(_ process: ClaudeProcess, hard: Bool = false) {
        ClaudeProcessScanner.kill(pid: process.pid, hard: hard)
        processes.removeAll { $0.pid == process.pid }
    }
}

struct ClaudeProcessesView: View {
    @StateObject private var vm = ClaudeProcessesViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if vm.isLoading && vm.processes.isEmpty {
                loadingState
            } else if vm.processes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(vm.processes.enumerated()), id: \.element.id) { index, p in
                            ProcessRow(process: p, onKill: { hard in vm.kill(p, hard: hard) })
                                .animation(Theme.Animations.staggered(index: index), value: vm.processes.count)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .onAppear { vm.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Processes").font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(vm.processes.count) running `claude` CLI process\(vm.processes.count == 1 ? "" : "es")")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { vm.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .keyboardShortcut("r")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Scanning…").font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No claude sessions running")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("When you run `claude` in a terminal, it will show up here.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProcessRow: View {
    let process: ClaudeProcess
    let onKill: (_ hard: Bool) -> Void
    @State private var hovering = false
    @State private var killing = false

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                StatusDot(status: .running)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(process.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown cwd")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if process.sessionId != nil {
                            Text("resume")
                                .font(Theme.Typography.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Colors.accentDim))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    if let cwd = process.cwd {
                        Text(cwd)
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("PID \(process.pid) · up \(RelativeTime.string(from: process.startedAt).replacingOccurrences(of: " ago", with: ""))")
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if hovering {
                    Button { triggerKill(hard: false) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.red)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
        }
        .scaleEffect(killing ? 0.97 : 1.0)
        .opacity(killing ? 0 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.Animations.easeOut, value: hovering)
        .contextMenu {
            if let cwd = process.cwd {
                Button("Open cwd in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                }
                Button("Copy cwd") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
                Divider()
            }
            Button("Kill (SIGTERM)") { triggerKill(hard: false) }
            Button("Force kill (SIGKILL)", role: .destructive) { triggerKill(hard: true) }
        }
    }

    private func triggerKill(hard: Bool) {
        withAnimation(Theme.Animations.springSnappy) { killing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onKill(hard) }
    }
}
