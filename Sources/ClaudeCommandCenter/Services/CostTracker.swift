import Foundation

enum CostTracker {
    static func loadAllEvents() -> [UsageEvent] {
        let fm = FileManager.default
        guard let projectFolders = try? fm.contentsOfDirectory(
            at: SessionReader.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var events: [UsageEvent] = []
        for folder in projectFolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let jsonlFiles = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "jsonl" } ?? []

            for url in jsonlFiles {
                events.append(contentsOf: parseEvents(from: url))
            }
        }
        return events
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseEvents(from url: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var cachedCwd: String?
        var events: [UsageEvent] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if cachedCwd == nil, let c = obj["cwd"] as? String, !c.isEmpty {
                cachedCwd = c
            }

            guard
                (obj["type"] as? String) == "assistant",
                let message = obj["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else { continue }

            let model = (message["model"] as? String) ?? "unknown"
            let input  = (usage["input_tokens"]  as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRead   = (usage["cache_read_input_tokens"]     as? Int) ?? 0

            let ts = parseDate(obj["timestamp"] as? String) ?? Date()
            let sessionId = (obj["sessionId"] as? String) ?? url.deletingPathExtension().lastPathComponent

            events.append(UsageEvent(
                timestamp: ts,
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheCreateTokens: cacheCreate,
                cacheReadTokens: cacheRead,
                projectPath: cachedCwd ?? "",
                sessionId: sessionId
            ))
        }
        return events
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoNoFraction.date(from: s)
    }

    // MARK: - Aggregations

    static func costToday(from events: [UsageEvent]) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        return events.filter { $0.timestamp >= start }.reduce(0) { $0 + $1.totalCost }
    }

    static func costThisMonth(from events: [UsageEvent]) -> Double {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        guard let start = cal.date(from: comps) else { return 0 }
        return events.filter { $0.timestamp >= start }.reduce(0) { $0 + $1.totalCost }
    }

    static func totalCost(from events: [UsageEvent]) -> Double {
        events.reduce(0) { $0 + $1.totalCost }
    }

    static func topProjects(from events: [UsageEvent], limit: Int = 10) -> [ProjectUsage] {
        let grouped = Dictionary(grouping: events, by: \.projectPath)
        return grouped.compactMap { (path, events) -> ProjectUsage? in
            guard !path.isEmpty else { return nil }
            let display = URL(fileURLWithPath: path).lastPathComponent
            let input  = events.reduce(0) { $0 + $1.inputTokens }
            let output = events.reduce(0) { $0 + $1.outputTokens }
            let cw     = events.reduce(0) { $0 + $1.cacheCreateTokens }
            let cr     = events.reduce(0) { $0 + $1.cacheReadTokens }
            let cost   = events.reduce(0.0) { $0 + $1.totalCost }
            let last   = events.map(\.timestamp).max()
            return ProjectUsage(
                id: path,
                projectPath: path,
                displayName: display,
                inputTokens: input,
                outputTokens: output,
                cacheCreateTokens: cw,
                cacheReadTokens: cr,
                cost: cost,
                lastActiveAt: last
            )
        }
        .sorted { $0.cost > $1.cost }
        .prefix(limit)
        .map { $0 }
    }

    static func dailySpend(from events: [UsageEvent], days: Int = 30) -> [DailySpend] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        let windowed = events.filter { $0.timestamp >= start }
        let grouped = Dictionary(grouping: windowed) { cal.startOfDay(for: $0.timestamp) }

        return (0..<days).compactMap { offset -> DailySpend? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let cost = grouped[day]?.reduce(0.0) { $0 + $1.totalCost } ?? 0
            return DailySpend(id: day, date: day, cost: cost)
        }
    }
}
