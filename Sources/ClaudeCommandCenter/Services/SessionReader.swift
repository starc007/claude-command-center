import Foundation

enum SessionReader {
    static let projectsRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }()

    /// Fast path: enumerate every JSONL, grab only file-level metadata
    /// (mtime, size), resolve the project path for each folder exactly once,
    /// and return a flat list of sessions sorted by recency.
    ///
    /// Does **not** parse JSONL contents — that's done lazily for stats.
    static func loadAllSessions() -> [Session] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [Session] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            guard let entries = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let jsonlFiles = entries.filter { $0.pathExtension == "jsonl" }
            guard !jsonlFiles.isEmpty else { continue }

            let projectPath = resolveProjectPath(folderName: folder.lastPathComponent, sampleJSONL: jsonlFiles.first)
            let projectName = URL(fileURLWithPath: projectPath).lastPathComponent

            for url in jsonlFiles {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = values?.contentModificationDate ?? .distantPast
                let size  = UInt64(values?.fileSize ?? 0)

                let sessionId = url.deletingPathExtension().lastPathComponent

                sessions.append(Session(
                    id: sessionId,
                    folderName: folder.lastPathComponent,
                    projectPath: projectPath,
                    projectName: projectName.isEmpty ? folder.lastPathComponent : projectName,
                    jsonlURL: url,
                    lastActiveAt: mtime,
                    fileSize: size
                ))
            }
        }
        return sessions.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// Rolls the flat session list back up into per-project summaries, used
    /// by the cost tracker + other legacy callers.
    static func loadAllProjects() -> [ProjectSummary] {
        let grouped = Dictionary(grouping: loadAllSessions(), by: \.folderName)
        return grouped.map { (folder, sessions) -> ProjectSummary in
            let first = sessions[0]
            return ProjectSummary(
                id: folder,
                projectPath: first.projectPath,
                projectName: first.projectName,
                sessionCount: sessions.count,
                lastActiveAt: sessions.map(\.lastActiveAt).max()
            )
        }
        .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
    }

    /// Reads a JSONL fully and returns (messageCount, inputTokens, outputTokens).
    /// Used lazily — NOT on the hot path during initial session list load.
    static func stats(for session: Session) -> (messages: Int, input: Int, output: Int) {
        guard let data = try? Data(contentsOf: session.jsonlURL),
              let text = String(data: data, encoding: .utf8) else { return (0, 0, 0) }
        var msgs = 0, input = 0, output = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let type = obj["type"] as? String, (type == "user" || type == "assistant") {
                msgs += 1
            }
            if let message = obj["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                input  += (usage["input_tokens"]  as? Int) ?? 0
                output += (usage["output_tokens"] as? Int) ?? 0
            }
        }
        return (msgs, input, output)
    }

    /// Reads the first user message text from a JSONL as a preview, without
    /// fully parsing the file.
    static func firstUserPrompt(for session: Session) -> String? {
        guard let data = try? Data(contentsOf: session.jsonlURL),
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(50) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "user",
                  let message = obj["message"] as? [String: Any]
            else { continue }
            if let str = message["content"] as? String { return str }
            if let arr = message["content"] as? [[String: Any]] {
                for block in arr {
                    if let t = block["text"] as? String, !t.isEmpty { return t }
                }
            }
        }
        return nil
    }

    // MARK: - Path resolution

    private static func resolveProjectPath(folderName: String, sampleJSONL: URL?) -> String {
        if let url = sampleJSONL,
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            // Read just the first 64KB — enough to hit a line that carries `cwd`.
            let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            if let text = String(data: chunk, encoding: .utf8) {
                for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(100) {
                    guard let lineData = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          let cwd = obj["cwd"] as? String, !cwd.isEmpty
                    else { continue }
                    return cwd
                }
            }
        }
        var decoded = folderName
        if decoded.hasPrefix("-") { decoded.removeFirst() }
        return "/" + decoded.replacingOccurrences(of: "-", with: "/")
    }
}
