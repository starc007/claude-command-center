import SwiftUI

@MainActor
final class MCPManagerViewModel: ObservableObject {
    @Published var servers: [MCPServer] = []
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) {
                MCPManager.loadAll()
            }.value
            self?.servers = list
            self?.isLoading = false
        }
    }

    func restart(_ server: MCPServer) {
        MCPManager.kill(server)
        // Optimistic: mark as stopped by removing pids; re-fetch shortly to confirm host respawned it.
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = MCPServer(
                id: server.id, name: server.name, command: server.command,
                args: server.args, envKeys: server.envKeys, source: server.source, pids: []
            )
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.load()
        }
    }

    var grouped: [(source: MCPSource, items: [MCPServer])] {
        let dict = Dictionary(grouping: servers, by: \.source)
        return [MCPSource.claudeCode, .claudeDesktop].compactMap { src in
            guard let items = dict[src], !items.isEmpty else { return nil }
            return (src, items)
        }
    }
}

struct MCPManagerView: View {
    @StateObject private var vm = MCPManagerViewModel()
    @State private var expandedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if vm.isLoading && vm.servers.isEmpty {
                loadingState
            } else if vm.servers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.grouped, id: \.source) { group in
                            section(source: group.source, items: group.items)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .onAppear { vm.load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MCP Servers").font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                let running = vm.servers.filter(\.isRunning).count
                Text("\(running) running · \(vm.servers.count) configured")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { vm.load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .keyboardShortcut("r")
        }
    }

    private func section(source: MCPSource, items: [MCPServer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.rawValue).sectionHeaderStyle()
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, server in
                    MCPRow(
                        server: server,
                        isExpanded: expandedID == server.id,
                        onToggle: { toggle(server.id) },
                        onRestart: { vm.restart(server) }
                    )
                    .animation(Theme.Animations.staggered(index: index), value: vm.servers.count)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(Theme.Animations.spring) {
            expandedID = (expandedID == id) ? nil : id
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading MCP config…").font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent").font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No MCP servers configured")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Add one to ~/.claude/.mcp.json or the Claude Desktop config.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MCPRow: View {
    let server: MCPServer
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRestart: () -> Void

    @State private var restarting = false

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Group {
                        if restarting {
                            ProgressView().controlSize(.small)
                        } else {
                            StatusDot(status: server.isRunning ? .running : .stopped)
                        }
                    }
                    .frame(width: 14)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(server.displayCommand)
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        if server.isRunning {
                            Button { triggerRestart() } label: {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Restart (kills the process; host will respawn)")
                        }
                        Button { onToggle() } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isExpanded {
                    Divider().overlay(Theme.Colors.border)
                    details
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private func triggerRestart() {
        withAnimation(Theme.Animations.springSnappy) { restarting = true }
        onRestart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Theme.Animations.spring) { restarting = false }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(label: "Command", value: server.command, mono: true)
            if !server.args.isEmpty {
                detailRow(label: "Args", value: server.args.joined(separator: " "), mono: true)
            }
            if !server.envKeys.isEmpty {
                detailRow(label: "Env", value: server.envKeys.joined(separator: ", "), mono: true)
            }
            if !server.pids.isEmpty {
                detailRow(label: "PIDs", value: server.pids.map { String($0) }.joined(separator: ", "), mono: true)
            }
        }
    }

    private func detailRow(label: String, value: String, mono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(mono ? Theme.Typography.monoSmall : Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}
