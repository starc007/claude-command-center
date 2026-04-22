import SwiftUI
import AppKit

enum TimeWindow: String, CaseIterable, Identifiable {
    case last24h = "24h"
    case last7d  = "7d"
    case archive = "Archive"

    var id: String { rawValue }
    func contains(_ date: Date) -> Bool {
        let delta = Date.now.timeIntervalSince(date)
        switch self {
        case .last24h: return delta <= 24 * 3600
        case .last7d:  return delta <= 7 * 24 * 3600
        case .archive: return delta >  7 * 24 * 3600
        }
    }
}

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var query: String = ""
    @Published var window: TimeWindow = .last24h
    @Published var gitStatuses: [String: GitStatus] = [:]        // projectPath -> status
    @Published var previews: [String: String] = [:]              // sessionId   -> first prompt

    @Published var contentSearchEnabled = false
    @Published var contentMatches: Set<String> = []              // folderName set
    @Published var contentSearching = false

    private var contentSearchTask: Task<Void, Never>?

    func load() {
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) {
                SessionReader.loadAllSessions()
            }.value
            self?.sessions = list
            self?.isLoading = false
            self?.loadGitStatuses(for: list)
            self?.loadPreviews(for: list)
        }
    }

    private func loadGitStatuses(for sessions: [Session]) {
        let paths = Array(Set(sessions.map(\.projectPath)))
        Task { [weak self] in
            let statuses = await Task.detached(priority: .utility) { () -> [String: GitStatus] in
                var result: [String: GitStatus] = [:]
                for path in paths {
                    if let s = GitService.status(at: path) { result[path] = s }
                }
                return result
            }.value
            self?.gitStatuses = statuses
        }
    }

    /// Trickles in prompt previews a few at a time so we don't block.
    private func loadPreviews(for sessions: [Session]) {
        Task { [weak self] in
            // Only preview the top N for speed; the rest show blank until scrolled.
            let top = Array(sessions.prefix(40))
            let map = await Task.detached(priority: .utility) { () -> [String: String] in
                var out: [String: String] = [:]
                for s in top {
                    if let p = SessionReader.firstUserPrompt(for: s) {
                        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        out[s.id] = String(trimmed.prefix(180))
                    }
                }
                return out
            }.value
            self?.previews = map
        }
    }

    func queryChanged() {
        contentSearchTask?.cancel()
        guard contentSearchEnabled else {
            contentMatches = []
            contentSearching = false
            return
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            contentMatches = []
            contentSearching = false
            return
        }
        contentSearching = true
        contentSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let matches = await Task.detached(priority: .utility) {
                SessionContentSearcher.folderIdsMatching(query: q)
            }.value
            if Task.isCancelled { return }
            await MainActor.run {
                self?.contentMatches = matches
                self?.contentSearching = false
            }
        }
    }

    func toggleContentSearch() {
        contentSearchEnabled.toggle()
        queryChanged()
    }

    // MARK: - Filtering + window counts

    func count(in window: TimeWindow) -> Int {
        sessions.filter { window.contains($0.lastActiveAt) }.count
    }

    var filtered: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sessions.filter { s in
            guard window.contains(s.lastActiveAt) else { return false }
            guard !q.isEmpty else { return true }

            let haystack = s.projectName.lowercased() + " " + s.projectPath.lowercased()
            if haystack.contains(q) { return true }
            if contentSearchEnabled, contentMatches.contains(s.folderName) { return true }
            return false
        }
    }
}

struct SessionListView: View {
    @StateObject private var vm = SessionListViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchBar
            timeWindowPicker

            if vm.isLoading && vm.sessions.isEmpty {
                loadingState
            } else if vm.filtered.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .onAppear { vm.load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(vm.sessions.count) total · \(vm.filtered.count) shown")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { vm.load() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.textSecondary)
            .keyboardShortcut("r")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField(
                vm.contentSearchEnabled ? "Search message content…" : "Search projects…",
                text: $vm.query
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .onChange(of: vm.query) { _, _ in vm.queryChanged() }

            if vm.contentSearching {
                ProgressView().controlSize(.mini)
            }
            Button {
                withAnimation(Theme.Animations.spring) { vm.toggleContentSearch() }
            } label: {
                Text("content")
                    .font(Theme.Typography.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule().fill(vm.contentSearchEnabled
                                       ? Theme.Colors.accentDim
                                       : Color.white.opacity(0.04))
                    )
                    .foregroundStyle(vm.contentSearchEnabled
                                     ? Theme.Colors.accent
                                     : Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Also search inside session message bodies")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    private var timeWindowPicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeWindow.allCases) { w in
                TimeWindowPill(
                    window: w,
                    count: vm.count(in: w),
                    selected: vm.window == w
                ) {
                    withAnimation(Theme.Animations.spring) { vm.window = w }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let groups = groupByProject(vm.filtered)
                ForEach(groups.indices, id: \.self) { i in
                    let group = groups[i]
                    if i > 0 { Spacer().frame(height: 8) }
                    ProjectGroupHeader(
                        name: group.projectName,
                        path: group.projectPath,
                        git: vm.gitStatuses[group.projectPath]
                    )
                    ForEach(group.sessions) { session in
                        SessionRow(
                            session: session,
                            preview: vm.previews[session.id],
                            onResume: {
                                TerminalLauncher.resumeSession(id: session.id, cwd: session.projectPath)
                            },
                            onExport: { SessionExporter.exportSession(session) }
                        )
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading ~/.claude/projects…")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(vm.query.isEmpty ? "Nothing in this window" : "No matches")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

    private struct ProjectGroup: Identifiable {
        let projectPath: String
        let projectName: String
        let sessions: [Session]
        var id: String { projectPath }
    }

    private func groupByProject(_ sessions: [Session]) -> [ProjectGroup] {
        var groups: [ProjectGroup] = []
        var currentPath: String?
        var buffer: [Session] = []
        var name = ""

        for session in sessions {
            if session.projectPath == currentPath {
                buffer.append(session)
            } else {
                if let p = currentPath, !buffer.isEmpty {
                    groups.append(ProjectGroup(projectPath: p, projectName: name, sessions: buffer))
                }
                currentPath = session.projectPath
                name = session.projectName
                buffer = [session]
            }
        }
        if let p = currentPath, !buffer.isEmpty {
            groups.append(ProjectGroup(projectPath: p, projectName: name, sessions: buffer))
        }
        return groups
    }
}

// MARK: - Row components

private struct TimeWindowPill: View {
    let window: TimeWindow
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(window.rawValue)
                    .font(Theme.Typography.body)
                Text("\(count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(selected ? Theme.Colors.textPrimary.opacity(0.7) : Theme.Colors.textTertiary)
            }
            .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.Colors.surfaceRaised : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectGroupHeader: View {
    let name: String
    let path: String
    let git: GitStatus?

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let git {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(git.branch ?? "detached")
                        .font(Theme.Typography.caption)
                    if git.hasChanges {
                        Circle().fill(Theme.Colors.yellow).frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6).padding(.bottom, 2)
    }
}

private struct SessionRow: View {
    let session: Session
    let preview: String?
    let onResume: () -> Void
    let onExport: () -> Void

    @State private var hovering = false

    private var isActive: Bool {
        Date.now.timeIntervalSince(session.lastActiveAt) < 90
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isActive {
                        StatusDot(status: .running)
                        Text("Running")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.green)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    if let preview {
                        Text(preview)
                            .font(Theme.Typography.body)
                            .foregroundStyle(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(session.id.prefix(8))
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            Spacer(minLength: 10)
            Text(RelativeTime.string(from: session.lastActiveAt))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.Colors.surface : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onResume() }
        .contextMenu {
            Button("Resume session") { onResume() }
            Button("Open cwd in Terminal") { TerminalLauncher.openTerminal(at: session.projectPath) }
            Divider()
            Button("Export as Markdown…") { onExport() }
            Button("Copy session id") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            Button("Copy project path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.projectPath, forType: .string)
            }
            Button("Reveal JSONL in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([session.jsonlURL])
            }
        }
    }
}
