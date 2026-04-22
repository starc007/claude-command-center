import SwiftUI
import Charts

@MainActor
final class CostTrackerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var today: Double = 0
    @Published var thisMonth: Double = 0
    @Published var total: Double = 0
    @Published var topProjects: [ProjectUsage] = []
    @Published var dailySpend: [DailySpend] = []

    // Animation targets
    @Published var todayAnimated: Double = 0
    @Published var monthAnimated: Double = 0
    @Published var totalAnimated: Double = 0

    func load() {
        isLoading = true
        Task { [weak self] in
            let events = await Task.detached(priority: .userInitiated) {
                CostTracker.loadAllEvents()
            }.value

            guard let self else { return }
            self.today = CostTracker.costToday(from: events)
            self.thisMonth = CostTracker.costThisMonth(from: events)
            self.total = CostTracker.totalCost(from: events)
            self.topProjects = CostTracker.topProjects(from: events, limit: 8)
            self.dailySpend = CostTracker.dailySpend(from: events, days: 30)
            self.isLoading = false

            withAnimation(.easeOut(duration: 0.9)) {
                self.todayAnimated = self.today
                self.monthAnimated = self.thisMonth
                self.totalAnimated = self.total
            }
        }
    }
}

struct CostTrackerView: View {
    @StateObject private var vm = CostTrackerViewModel()
    @State private var chartProgress: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stats
                chartSection
                projectsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .onAppear {
            vm.load()
            chartProgress = 0
            withAnimation(.easeOut(duration: 1.1)) { chartProgress = 1 }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cost").font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Token usage + spend across all Claude Code sessions")
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

    private var stats: some View {
        HStack(spacing: 14) {
            StatCard(label: "Today", value: vm.todayAnimated)
            StatCard(label: "This month", value: vm.monthAnimated)
            StatCard(label: "All time", value: vm.totalAnimated, accent: true)
        }
    }

    private var chartSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("30-day spend").sectionHeaderStyle()
                if vm.dailySpend.isEmpty {
                    Text("No usage yet.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    spendChart.frame(height: 160)
                }
            }
        }
    }

    private var spendChart: some View {
        Chart(vm.dailySpend) { day in
            AreaMark(
                x: .value("Date", day.date),
                y: .value("Cost", day.cost * chartProgress)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.Colors.accent.opacity(0.35), Theme.Colors.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Date", day.date),
                y: .value("Cost", day.cost * chartProgress)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Theme.Colors.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.Colors.border)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.asUSD())
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine().foregroundStyle(Theme.Colors.border)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top projects").sectionHeaderStyle()
            if vm.topProjects.isEmpty {
                GlassCard {
                    Text("No project usage yet.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(vm.topProjects.enumerated()), id: \.element.id) { index, p in
                        ProjectCostRow(project: p)
                            .animation(Theme.Animations.staggered(index: index), value: vm.topProjects.count)
                    }
                }
            }
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: Double
    var accent: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).sectionHeaderStyle()
                AnimatedCounter(
                    value: value,
                    color: accent ? Theme.Colors.accent : Theme.Colors.textPrimary
                ) { v in v.asUSD() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProjectCostRow: View {
    let project: ProjectUsage

    var body: some View {
        GlassCard(padding: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(project.projectPath)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(project.cost.asUSD())
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("in \(Double(project.inputTokens).compactInt()) · out \(Double(project.outputTokens).compactInt())")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}
