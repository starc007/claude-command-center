import SwiftUI

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var projects: [ProjectSession] = []
    @Published var isLoading = false
    @Published var query: String = ""

    func load() {
        isLoading = true
        Task { [weak self] in
            let all = await Task.detached(priority: .userInitiated) {
                SessionReader.loadAllProjects()
            }.value
            self?.projects = all
            self?.isLoading = false
        }
    }

    var filtered: [ProjectSession] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter { p in
            p.displayName.lowercased().contains(q) ||
            p.projectPath.lowercased().contains(q)
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
            TextField("Search projects…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
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
                    SessionRow(project: project, isSelected: selection == project.id)
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
                            Text("\(project.sessionCount)")
                                .font(Theme.Typography.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Theme.Colors.accentDim)
                                )
                                .foregroundStyle(Theme.Colors.accent)
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
}
