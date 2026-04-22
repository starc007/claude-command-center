import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case sessions  = "Sessions"
    case processes = "Processes"
    case ports     = "Ports"
    case cost      = "Cost"
    case mcp       = "MCP Servers"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sessions:  return "square.stack.3d.up"
        case .processes: return "bolt.circle"
        case .ports:     return "network"
        case .cost:      return "chart.line.uptrend.xyaxis"
        case .mcp:       return "cube.transparent"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarSection? = .sessions

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 18)
                        Text(section.rawValue).font(Theme.Typography.body)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
                .id(selection?.id ?? "none")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 14)),
                    removal:   .opacity.combined(with: .offset(x: -14))
                ))
                .animation(Theme.Animations.spring, value: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .sessions:  SessionListView()
        case .processes: ClaudeProcessesView()
        case .ports:     PortManagerView()
        case .cost:      CostTrackerView()
        case .mcp:       MCPManagerView()
        case .none:      PlaceholderView(title: "Welcome",  subtitle: "Select a section to get started")
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle).font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming soon").sectionHeaderStyle()
                    Text("This section will be wired up in an upcoming commit.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(24)
    }
}
