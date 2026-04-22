import Foundation

struct MCPLogSnapshot: Hashable, Sendable {
    let lastError: String?
    let lastErrorAt: Date?
    let logPath: String?
    let logExists: Bool
}

enum MCPLogReader {
    private static let logsDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Claude", directoryHint: .isDirectory)

    private static let tailBytes = 64 * 1024
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Reads the tail of `~/Library/Logs/Claude/mcp-server-<name>.log` and
    /// returns the most recent warn/error line it finds (if any).
    static func snapshot(forServerNamed name: String) -> MCPLogSnapshot {
        let url = logsDir.appending(path: "mcp-server-\(name).log")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return MCPLogSnapshot(lastError: nil, lastErrorAt: nil, logPath: url.path, logExists: false)
        }

        guard let text = tail(url: url, bytes: tailBytes) else {
            return MCPLogSnapshot(lastError: nil, lastErrorAt: nil, logPath: url.path, logExists: true)
        }

        // Walk lines in reverse; return the first line that looks like an error/warn.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("[error]") || lower.contains("[warn]")
               || lower.contains(" error ") || lower.contains(" fatal ") {
                let (ts, msg) = splitTimestamp(String(line))
                return MCPLogSnapshot(lastError: msg, lastErrorAt: ts, logPath: url.path, logExists: true)
            }
        }
        return MCPLogSnapshot(lastError: nil, lastErrorAt: nil, logPath: url.path, logExists: true)
    }

    // MARK: - Helpers

    private static func tail(url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch { return nil }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        do {
            try handle.seek(toOffset: offset)
        } catch { return nil }
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Splits "<iso-timestamp> [name] [level] rest..." into (date, rest).
    private static func splitTimestamp(_ line: String) -> (Date?, String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return (nil, line) }
        let date = iso.date(from: String(parts[0]))
        return (date, String(parts[1]))
    }
}
