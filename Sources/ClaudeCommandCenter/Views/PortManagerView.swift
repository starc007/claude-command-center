import SwiftUI

@MainActor
final class PortManagerViewModel: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var isLoading = false
    @Published var query: String = ""

    func refresh() {
        isLoading = true
        Task { [weak self] in
            let fresh = await Task.detached(priority: .userInitiated) {
                PortManager.listListeningPorts()
            }.value
            self?.ports = fresh
            self?.isLoading = false
        }
    }

    func kill(_ port: PortInfo, hard: Bool = false) {
        PortManager.kill(pid: port.pid, hard: hard)
        // Optimistic remove; the next refresh confirms.
        ports.removeAll { $0.id == port.id }
    }

    func killAll(in family: ProcessFamily) {
        let pids = Set(ports.filter { $0.family == family }.map(\.pid))
        for pid in pids { PortManager.kill(pid: pid) }
        ports.removeAll { pids.contains($0.pid) }
    }

    var filtered: [PortInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ports }
        return ports.filter { p in
            "\(p.port)".contains(q) ||
            p.processName.lowercased().contains(q) ||
            p.commandPath.lowercased().contains(q)
        }
    }

    var grouped: [(family: ProcessFamily, items: [PortInfo])] {
        let groupDict = Dictionary(grouping: filtered, by: \.family)
        return ProcessFamily.allCases
            .compactMap { fam in
                guard let items = groupDict[fam], !items.isEmpty else { return nil }
                return (fam, items)
            }
    }
}

struct PortManagerView: View {
    @StateObject private var vm = PortManagerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchBar

            if vm.isLoading && vm.ports.isEmpty {
                loadingState
            } else if vm.grouped.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.grouped, id: \.family) { group in
                            groupSection(family: group.family, items: group.items)
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
                Text("Ports").font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(vm.ports.count) listening ports")
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textSecondary)
            TextField("Search by port, process, or path…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    private func groupSection(family: ProcessFamily, items: [PortInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: family.symbol).foregroundStyle(Theme.Colors.accent)
                Text(family.title).sectionHeaderStyle()
                Text("\(items.count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                if items.count > 1 {
                    Button("kill all") { vm.killAll(in: family) }
                        .buttonStyle(.plain)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.red)
                }
            }
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PortRow(port: item, onKill: { hard in vm.kill(item, hard: hard) })
                        .animation(Theme.Animations.staggered(index: index), value: vm.ports.count)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Scanning ports…").font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network.slash")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(vm.query.isEmpty ? "Nothing listening" : "No matches")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PortRow: View {
    let port: PortInfo
    let onKill: (_ hard: Bool) -> Void

    @State private var offset: CGFloat = 0
    @State private var killing = false
    @State private var hovering = false

    private let killThreshold: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            // Kill background revealed on swipe
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("kill").font(Theme.Typography.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Colors.red)
            )
            .opacity(min(1, -offset / killThreshold))

            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(":\(port.port)")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(port.processName)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        HStack(spacing: 8) {
                            Text("PID \(port.pid)")
                                .font(Theme.Typography.monoSmall)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            if let started = port.startedAt {
                                Text("· \(RelativeTime.string(from: started))")
                                    .font(Theme.Typography.monoSmall)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    killButton
                        .opacity(hovering ? 1 : 0.0)
                        .animation(Theme.Animations.easeOut, value: hovering)
                }
            }
            .offset(x: offset)
            .scaleEffect(killing ? 0.97 : 1.0)
            .opacity(killing ? 0.0 : 1.0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = min(0, value.translation.width)
                    }
                    .onEnded { _ in
                        if offset < -killThreshold {
                            confirmKill(hard: false)
                        } else {
                            withAnimation(Theme.Animations.spring) { offset = 0 }
                        }
                    }
            )
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Kill (SIGTERM)") { confirmKill(hard: false) }
            Button("Force kill (SIGKILL)", role: .destructive) { confirmKill(hard: true) }
            Divider()
            Button("Copy command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(port.commandPath, forType: .string)
            }
        }
    }

    private var killButton: some View {
        Button { confirmKill(hard: false) } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.Colors.red)
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
    }

    private func confirmKill(hard: Bool) {
        withAnimation(Theme.Animations.springSnappy) { killing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onKill(hard)
        }
    }
}
