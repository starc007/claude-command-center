import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
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
            List(SidebarSection.allCases, id: \.self, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
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
        case nil:        EmptyView()
        }
    }
}
