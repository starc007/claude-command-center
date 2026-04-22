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
    @Published var activeTagFilter: String?
    @Published var gitStatuses: [String: GitStatus] = [:]
    @Published var previews: [String: String] = [:]
    @Published var selection: Set<String> = []
    @Published var analyticsVersion = 0

    @Published var contentSearchEnabled = false
    @Published var contentMatches: Set<String> = []
    @Published var contentSearching = false

    private var contentSearchTask: Task<Void, Never>?
    private let metaStore = SessionMetadataStore.shared
    private let analyzer = SessionAnalyzer.shared

    init() {
        NotificationCenter.default.addObserver(
            forName: .sessionAnalyticsUpdated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.analyticsVersion &+= 1 }
        }
    }

    func load() {
        isLoading = true
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) {
                SessionReader.loadAllSessions()
            }.value
            guard let self else { return }
            self.sessions = list
            self.isLoading = false
            self.loadGitStatuses(for: list)
            self.loadPreviews(for: list)
            await self.analyzer.preload(Array(list.prefix(150)))
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

    private func loadPreviews(for sessions: [Session]) {
        Task { [weak self] in
            let top = Array(sessions.prefix(60))
            let map = await Task.detached(priority: .utility) { () -> [String: String] in
                var out: [String: String] = [:]
                for s in top {
                    if let p = SessionReader.firstUserPrompt(for: s) {
                        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        out[s.id] = String(trimmed.prefix(240))
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

    func count(in window: TimeWindow) -> Int {
        sessions.filter { window.contains($0.lastActiveAt) }.count
    }

    func tagCounts() -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in sessions {
            for t in metaStore.meta(for: s.id).tags {
                counts[t, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    /// Returns (pinned, unpinned-filtered-by-window).
    var partitioned: (pinned: [Session], regular: [Session]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var pinned: [Session] = []
        var regular: [Session] = []

        for s in sessions {
            let meta = metaStore.meta(for: s.id)
            if meta.archived { continue }

            if !q.isEmpty {
                let matchesSurface = s.projectName.lowercased().contains(q)
                    || s.projectPath.lowercased().contains(q)
                    || meta.note.lowercased().contains(q)
                    || meta.tags.contains { $0.lowercased().contains(q) }
                let matchesContent = contentSearchEnabled && contentMatches.contains(s.folderName)
                if !(matchesSurface || matchesContent) { continue }
            }

            if let tag = activeTagFilter, !meta.tags.contains(tag) { continue }

            if meta.pinned {
                pinned.append(s)
            } else if window.contains(s.lastActiveAt) {
                regular.append(s)
            }
        }
        return (pinned, regular)
    }

    // MARK: - Selection + bulk ops

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func clearSelection() { selection.removeAll() }

    var selectedSessions: [Session] {
        sessions.filter { selection.contains($0.id) }
    }

    func archiveSelected() {
        let targets = selectedSessions
        SessionArchiver.archive(targets)
        for s in targets { metaStore.setArchived(true, for: s.id) }
        clearSelection()
        load()
    }

    func deleteSelected() {
        let targets = selectedSessions
        SessionArchiver.delete(targets)
        for s in targets { metaStore.remove(s.id) }
        clearSelection()
        load()
    }

    func exportSelected() {
        let targets = selectedSessions
        for t in targets { SessionExporter.exportSession(t) }
        clearSelection()
    }

    func tagSelected(with tag: String) {
        for s in selectedSessions { metaStore.addTag(tag, to: s.id) }
    }
}

// MARK: - View

struct SessionListView: View {
    @StateObject private var vm = SessionListViewModel()
    @ObservedObject private var metaStore = SessionMetadataStore.shared
    @State private var editorSession: Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchBar
            timeWindowPicker
            tagFilterBar

            if vm.isLoading && vm.sessions.isEmpty {
                loadingState
            } else {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .onAppear { vm.load() }
        .sheet(item: $editorSession) { session in
            SessionEditorSheet(session: session)
        }
        .overlay(alignment: .bottom) {
            if !vm.selection.isEmpty {
                bulkActionBar
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Animations.spring, value: vm.selection.isEmpty)
    }

    // MARK: - Header + filters

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(vm.sessions.count) total · \(vm.partitioned.regular.count + vm.partitioned.pinned.count) visible")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button { vm.load() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.textSecondary)
            .keyboardShortcut("r")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField(
                vm.contentSearchEnabled ? "Search message content…" : "Search projects, notes, tags…",
                text: $vm.query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.Colors.textPrimary)
            .onChange(of: vm.query) { _, _ in vm.queryChanged() }

            if vm.contentSearching { ProgressView().controlSize(.mini) }

            Button {
                withAnimation(Theme.Animations.spring) { vm.toggleContentSearch() }
            } label: {
                Text("content")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous).fill(
                            vm.contentSearchEnabled
                            ? Theme.Colors.accentDim
                            : Color.white.opacity(0.04)
                        )
                    )
                    .foregroundStyle(vm.contentSearchEnabled
                                     ? Theme.Colors.accent
                                     : Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Also search inside session message bodies")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
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
    private var tagFilterBar: some View {
        let tags = vm.tagCounts()
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(
                        label: "All",
                        selected: vm.activeTagFilter == nil,
                        count: nil,
                        color: nil
                    ) {
                        withAnimation(Theme.Animations.spring) { vm.activeTagFilter = nil }
                    }
                    ForEach(tags, id: \.tag) { entry in
                        FilterChip(
                            label: entry.tag,
                            selected: vm.activeTagFilter == entry.tag,
                            count: entry.count,
                            color: TagStyle.color(for: entry.tag)
                        ) {
                            withAnimation(Theme.Animations.spring) {
                                vm.activeTagFilter = (vm.activeTagFilter == entry.tag) ? nil : entry.tag
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Body

    private var content: some View {
        let parts = vm.partitioned
        return ScrollView {
            LazyVStack(spacing: 4) {
                if !parts.pinned.isEmpty {
                    pinnedSection(parts.pinned)
                }
                if parts.regular.isEmpty && parts.pinned.isEmpty {
                    emptyState
                        .frame(minHeight: 240)
                } else if !parts.regular.isEmpty {
                    ForEach(groupByProject(parts.regular)) { group in
                        projectGroup(group, collapsible: false)
                    }
                }
            }
            .padding(.bottom, vm.selection.isEmpty ? 16 : 72)
        }
    }

    @ViewBuilder
    private func pinnedSection(_ sessions: [Session]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill").font(.system(size: 9))
            Text("PINNED")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
        }
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, 4)
        .padding(.top, 6).padding(.bottom, 4)

        ForEach(sessions) { session in
            sessionRow(session)
        }
        Spacer().frame(height: 10)
    }

    private func projectGroup(_ group: ProjectGroup, collapsible: Bool) -> some View {
        VStack(spacing: 4) {
            ProjectGroupHeader(
                name: group.projectName,
                path: group.projectPath,
                git: vm.gitStatuses[group.projectPath]
            )
            ForEach(group.sessions) { session in
                sessionRow(session)
            }
            Spacer().frame(height: 10)
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        SessionRow(
            session: session,
            preview: vm.previews[session.id],
            analytics: SessionAnalyzer.shared.analytics(for: session),
            meta: metaStore.meta(for: session.id),
            isSelected: vm.selection.contains(session.id),
            anySelected: !vm.selection.isEmpty,
            onToggleSelection: { vm.toggleSelection(session.id) },
            onTogglePin: { metaStore.togglePin(session.id) },
            onResume: {
                TerminalLauncher.resumeSession(id: session.id, cwd: session.projectPath)
            },
            onExport: { SessionExporter.exportSession(session) },
            onEdit: { editorSession = session }
        )
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        HStack(spacing: 14) {
            Text("\(vm.selection.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)

            Divider().frame(height: 14).overlay(Theme.Colors.border)

            bulkButton(icon: "square.and.arrow.down", label: "Export") { vm.exportSelected() }
            bulkButton(icon: "archivebox", label: "Archive") { vm.archiveSelected() }
            bulkButton(icon: "trash", label: "Delete", destructive: true) { vm.deleteSelected() }

            Spacer()

            Button { vm.clearSelection() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Colors.surfaceRaised)
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Theme.Colors.borderStrong, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        )
    }

    private func bulkButton(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(destructive ? Theme.Colors.red : Theme.Colors.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading / empty

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading ~/.claude/projects…")
                .font(.system(size: 11))
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
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grouping

    struct ProjectGroup: Identifiable {
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

// MARK: - Subviews

private struct TimeWindowPill: View {
    let window: TimeWindow
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(window.rawValue)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 10))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let git {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(git.branch ?? "detached").font(.system(size: 10))
                    if git.hasChanges {
                        Circle().fill(Theme.Colors.yellow).frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Rectangle()
                .fill(Theme.Colors.border)
                .frame(height: 1)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8).padding(.bottom, 4)
    }
}

private struct SessionRow: View {
    let session: Session
    let preview: String?
    let analytics: SessionAnalytics?
    let meta: SessionMetadata
    let isSelected: Bool
    let anySelected: Bool
    let onToggleSelection: () -> Void
    let onTogglePin: () -> Void
    let onResume: () -> Void
    let onExport: () -> Void
    let onEdit: () -> Void

    @State private var hovering = false

    private var isActive: Bool {
        Date.now.timeIntervalSince(session.lastActiveAt) < 90
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            selectionGutter
            VStack(alignment: .leading, spacing: 6) {
                primaryLine
                metadataLine
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Colors.accent.opacity(0.6) : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if anySelected { onToggleSelection() } }
        .onTapGesture(count: 2) { onResume() }
        .contextMenu { contextMenu }
    }

    private var selectionGutter: some View {
        let show = hovering || anySelected
        return Button(action: onToggleSelection) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .opacity(show ? 1 : 0)
        .animation(Theme.Animations.easeOut, value: show)
        .padding(.top, 1)
    }

    private var primaryLine: some View {
        HStack(spacing: 6) {
            if meta.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.accent)
            }
            if isActive {
                StatusDot(status: .running)
            }
            Text(primaryText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(primaryColor)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    private var primaryText: String {
        if let preview, !preview.isEmpty { return preview }
        return "Session \(String(session.id.prefix(8)))"
    }

    private var primaryColor: Color {
        if !meta.note.isEmpty { return Theme.Colors.textPrimary }
        return isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
    }

    @ViewBuilder
    private var metadataLine: some View {
        HStack(spacing: 6) {
            ForEach(meta.tags, id: \.self) { tag in
                TagChip(name: tag)
            }
            if let analytics, let model = analytics.model {
                MonoPill(text: analytics.shortModel)
                    .help(model)
            }
            if let duration = analytics?.duration, duration > 1 {
                MetaIconText(icon: "clock", text: formatDuration(duration))
            }
            if let count = analytics?.messageCount, count > 0 {
                MetaIconText(icon: "bubble.left.and.bubble.right", text: "\(count)")
            }
            if !meta.note.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .help(meta.note)
            }
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(RelativeTime.string(from: session.lastActiveAt))
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.textTertiary)

            if hovering {
                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }.buttonStyle(.plain).help("Edit tags / note / pin")

                    Button(action: onResume) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.accent)
                    }.buttonStyle(.plain).help("Resume in terminal")
                }
                .transition(.opacity.combined(with: .offset(x: 4)))
            }
        }
        .animation(Theme.Animations.easeOut, value: hovering)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                isSelected
                ? Theme.Colors.accent.opacity(0.08)
                : (hovering ? Theme.Colors.surface : Color.clear)
            )
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Resume session") { onResume() }
        Button("Open cwd in Terminal") { TerminalLauncher.openTerminal(at: session.projectPath) }
        Divider()
        Button(meta.pinned ? "Unpin" : "Pin to top") { onTogglePin() }
        Button("Edit tags / note…") { onEdit() }
        Divider()
        Button("Export as Markdown…") { onExport() }
        Button("Copy session id") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.id, forType: .string)
        }
        Button("Reveal JSONL in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([session.jsonlURL])
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 { return "\(Int(duration))s" }
        if duration < 3600 { return "\(Int(duration / 60))m" }
        let h = Int(duration / 3600)
        let m = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

private struct MonoPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(Theme.Colors.textSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule(style: .continuous).strokeBorder(Theme.Colors.border, lineWidth: 0.5))
            )
    }
}

private struct MetaIconText: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }
        .foregroundStyle(Theme.Colors.textTertiary)
    }
}
