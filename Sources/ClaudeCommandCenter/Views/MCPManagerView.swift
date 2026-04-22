import SwiftUI

@MainActor
final class MCPManagerViewModel: ObservableObject {
    @Published var servers: [MCPServer] = []
    @Published var logs: [String: MCPLogSnapshot] = [:]  // server.name -> snapshot
    @Published var isLoading = false

    func load() {
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) {
                MCPManager.loadAll()
            }.value
            self?.servers = list
            self?.isLoading = false
            self?.loadLogs(for: list)
        }
    }

    private func loadLogs(for servers: [MCPServer]) {
        let names = Array(Set(servers.map(\.name)))
        Task { [weak self] in
            let snaps = await Task.detached(priority: .utility) { () -> [String: MCPLogSnapshot] in
                var out: [String: MCPLogSnapshot] = [:]
                for name in names {
                    out[name] = MCPLogReader.snapshot(forServerNamed: name)
                }
                return out
            }.value
            self?.logs = snaps
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
    @State private var showingAddSheet = false

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
        .sheet(isPresented: $showingAddSheet) {
            AddMCPServerSheet { vm.load() }
        }
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
            Button { showingAddSheet = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add").font(Theme.Typography.body)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.Colors.accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n")

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
                        log: vm.logs[server.name],
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
    let log: MCPLogSnapshot?
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
                        HStack(spacing: 8) {
                            Text(server.name)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if let log, log.lastError != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("log")
                                        .font(Theme.Typography.caption)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Colors.yellow.opacity(0.15)))
                                .foregroundStyle(Theme.Colors.yellow)
                                .help("Warnings or errors present in the server log")
                            }
                        }
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
            if let log, let msg = log.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.yellow)
                            .font(.system(size: 11))
                        Text("Last warning / error")
                            .sectionHeaderStyle()
                        if let at = log.lastErrorAt {
                            Text(RelativeTime.string(from: at))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Text(msg)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            if let path = log?.logPath, log?.logExists == true {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text").font(.system(size: 10))
                        Text("Reveal log").font(Theme.Typography.caption)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
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
