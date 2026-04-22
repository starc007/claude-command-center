import SwiftUI

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var projects: [ProjectSession] = []
    @Published var isLoading = false
    @Published var query: String = ""
    @Published var gitStatuses: [String: GitStatus] = [:]   // projectPath -> GitStatus
    @Published var contentSearchEnabled = false
    @Published var contentMatches: Set<String> = []         // folderName set
    @Published var contentSearching = false

    private var contentSearchTask: Task<Void, Never>?

    func load() {
        isLoading = true
        Task { [weak self] in
            let all = await Task.detached(priority: .userInitiated) {
                SessionReader.loadAllProjects()
            }.value
            self?.projects = all
            self?.isLoading = false
            self?.loadGitStatuses(for: all)
        }
    }

    private func loadGitStatuses(for projects: [ProjectSession]) {
        let paths = projects.map(\.projectPath)
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
            // Debounce: wait 250ms before committing to a scan.
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

    var filtered: [ProjectSession] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }

        return projects.filter { p in
            let byNameOrPath =
                p.displayName.lowercased().contains(q) ||
                p.projectPath.lowercased().contains(q)
            if byNameOrPath { return true }
            if contentSearchEnabled, contentMatches.contains(p.folderName) { return true }
            return false
        }
    }
}

struct SessionListView: View {
    @StateObject private var vm = SessionListViewModel()
    @State private var selection: ProjectSession.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            searchBar

            if vm.isLoading && vm.projects.isEmpty {
                loadingState
            } else if vm.filtered.isEmpty {
                emptyState
            } else {
                list
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
                Text("Sessions").font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(vm.projects.count) projects in ~/.claude/projects")
                    .font(Theme.Typography.body)
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
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(vm.contentSearchEnabled
                      ? "Search message content…"
                      : "Search projects…",
                      text: $vm.query)
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
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 11))
                    Text("content").font(Theme.Typography.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(vm.contentSearchEnabled ? Theme.Colors.accentDim : Color.white.opacity(0.04))
                )
                .foregroundStyle(vm.contentSearchEnabled ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Also search inside session messages")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                )
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(vm.filtered.enumerated()), id: \.element.id) { index, project in
                    SessionRow(
                        project: project,
                        git: vm.gitStatuses[project.projectPath],
                        isSelected: selection == project.id
                    )
                    .onTapGesture { selection = project.id }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                    .animation(Theme.Animations.staggered(index: index), value: vm.projects.count)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Reading sessions…").font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(vm.query.isEmpty ? "No projects found" : "No matches")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(vm.query.isEmpty
                 ? "Start a Claude Code session and it will show up here."
                 : "Try a different search term.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let project: ProjectSession
    let git: GitStatus?
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.displayName)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        if project.sessionCount > 1 {
                            countBadge(value: project.sessionCount)
                        }
                        if let git = git {
                            gitPill(git: git)
                        }
                    }
                    Text(project.projectPath)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(RelativeTime.string(from: project.lastActiveAt))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text("\(project.messageCount) msgs")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                resumeButton
                    .opacity(hovering ? 1 : 0.0)
                    .animation(Theme.Animations.easeOut, value: hovering)
            }
        }
        .scaleEffect(hovering ? 1.005 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.Colors.accent : .clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(Theme.Animations.springSnappy, value: hovering)
        .contextMenu {
            Button("Resume in Terminal") {
                TerminalLauncher.resumeClaude(at: project.projectPath)
            }
            Button("Open Terminal here") {
                TerminalLauncher.openTerminal(at: project.projectPath)
            }
            Divider()
            Button("Export as Markdown…") {
                SessionExporter.exportProject(project)
            }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.projectPath, forType: .string)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: project.projectPath)]
                )
            }
        }
    }

    private var resumeButton: some View {
        Button {
            TerminalLauncher.resumeClaude(at: project.projectPath)
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Colors.accent)
        }
        .buttonStyle(.plain)
        .help("Resume with `claude --continue`")
    }

    private func countBadge(value: Int) -> some View {
        Text("\(value)")
            .font(Theme.Typography.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.Colors.accentDim))
            .foregroundStyle(Theme.Colors.accent)
    }

    private func gitPill(git: GitStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
            Text(git.branch ?? "detached")
                .font(Theme.Typography.caption)
            if git.hasChanges {
                Circle()
                    .fill(Theme.Colors.yellow)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
        )
        .foregroundStyle(git.hasChanges ? Theme.Colors.yellow : Theme.Colors.textSecondary)
        .help(
            git.hasChanges
            ? "\(git.modifiedCount) modified, \(git.untrackedCount) untracked"
            : "Clean working tree"
        )
    }
}
