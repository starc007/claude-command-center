import Foundation

enum SessionReader {
    static let projectsRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }()

    static func loadAllProjects() -> [ProjectSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { loadProject(at: $0) }
            .sorted { (a, b) in
                (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
            }
    }

    private static func loadProject(at folderURL: URL) -> ProjectSession? {
        let folderName = folderURL.lastPathComponent
        let fm = FileManager.default

        guard let children = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let jsonlFiles = children.filter { $0.pathExtension == "jsonl" }
        guard !jsonlFiles.isEmpty else { return nil }

        var latest: Date?
        for url in jsonlFiles {
            if let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                if latest == nil || mod > latest! { latest = mod }
            }
        }

        let stats = aggregateStats(from: jsonlFiles)
        let projectPath = resolveProjectPath(folderName: folderName, sampleJSONL: jsonlFiles.first)
        let display = URL(fileURLWithPath: projectPath).lastPathComponent

        return ProjectSession(
            id: folderName,
            folderName: folderName,
            projectPath: projectPath,
            displayName: display.isEmpty ? folderName : display,
            sessionCount: jsonlFiles.count,
            messageCount: stats.messageCount,
            lastActiveAt: latest,
            inputTokens: stats.inputTokens,
            outputTokens: stats.outputTokens
        )
    }

    private struct AggregateStats {
        var messageCount = 0
        var inputTokens  = 0
        var outputTokens = 0
    }

    private static func aggregateStats(from jsonlFiles: [URL]) -> AggregateStats {
        var stats = AggregateStats()
        for url in jsonlFiles {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }
                if let type = obj["type"] as? String, (type == "user" || type == "assistant") {
                    stats.messageCount += 1
                }
                if let message = obj["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    stats.inputTokens  += (usage["input_tokens"]  as? Int) ?? 0
                    stats.outputTokens += (usage["output_tokens"] as? Int) ?? 0
                }
            }
        }
        return stats
    }

    /// Prefer the `cwd` field on any real user/assistant entry in the JSONL,
    /// since the folder-name encoding (/ → -) is ambiguous for paths with dashes.
    private static func resolveProjectPath(folderName: String, sampleJSONL: URL?) -> String {
        if let url = sampleJSONL,
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(100) {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let cwd = obj["cwd"] as? String, !cwd.isEmpty
                else { continue }
                return cwd
            }
        }
        // Fallback: best-effort decode (leading `-` becomes `/`, subsequent `-` become `/`).
        // This is lossy — paths containing a real hyphen get mangled. Used only when no cwd is found.
        var decoded = folderName
        if decoded.hasPrefix("-") { decoded.removeFirst() }
        return "/" + decoded.replacingOccurrences(of: "-", with: "/")
    }
}
