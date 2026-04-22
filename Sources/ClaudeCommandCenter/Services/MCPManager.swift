import Foundation
import Darwin

enum MCPManager {
    static let claudeCodeConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".claude/.mcp.json")

    static let claudeDesktopConfigPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Claude/claude_desktop_config.json")

    static func loadAll() -> [MCPServer] {
        let psSnapshot = PSSnapshot.capture()
        var out: [MCPServer] = []
        out.append(contentsOf: loadConfig(at: claudeCodeConfigPath, source: .claudeCode, ps: psSnapshot))
        out.append(contentsOf: loadConfig(at: claudeDesktopConfigPath, source: .claudeDesktop, ps: psSnapshot))
        return out.sorted { a, b in
            if a.source == b.source { return a.name < b.name }
            return a.source.rawValue < b.source.rawValue
        }
    }

    static func kill(_ server: MCPServer, hard: Bool = false) {
        for pid in server.pids {
            _ = Darwin.kill(pid, hard ? SIGKILL : SIGTERM)
        }
    }

    // MARK: - Config parsing

    private struct ConfigFile: Decodable {
        let mcpServers: [String: ServerEntry]?
    }
    private struct ServerEntry: Decodable {
        let command: String?
        let args: [String]?
        let env: [String: String]?
    }

    private static func loadConfig(at url: URL, source: MCPSource, ps: PSSnapshot) -> [MCPServer] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let parsed = try? JSONDecoder().decode(ConfigFile.self, from: data) else { return [] }
        guard let entries = parsed.mcpServers else { return [] }

        return entries.map { (name, entry) in
            let cmd = entry.command ?? ""
            let args = entry.args ?? []
            let envKeys = Array((entry.env ?? [:]).keys).sorted()
            let pids = ps.findMatches(command: cmd, args: args)

            return MCPServer(
                id: "\(source.rawValue)::\(name)",
                name: name,
                command: cmd,
                args: args,
                envKeys: envKeys,
                source: source,
                pids: pids
            )
        }
    }
}

/// Snapshot of `ps` output used to match MCP configs to running processes.
struct PSSnapshot: Sendable {
    struct Entry: Sendable {
        let pid: Int32
        let command: String
    }
    let entries: [Entry]

    static func capture() -> PSSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return PSSnapshot(entries: []) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return PSSnapshot(entries: []) }

        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.drop(while: { $0 == " " })
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = trimmed[..<spaceIdx]
            let cmd = trimmed[trimmed.index(after: spaceIdx)...]
            guard let pid = Int32(pidStr) else { continue }
            entries.append(Entry(pid: pid, command: String(cmd)))
        }
        return PSSnapshot(entries: entries)
    }

    /// Match heuristic: the MCP server command + first arg must appear as
    /// substrings (in order) in the process command line.
    func findMatches(command: String, args: [String]) -> [Int32] {
        guard !command.isEmpty else { return [] }
        let cmdBasename = URL(fileURLWithPath: command).lastPathComponent
        let needle = args.first ?? ""

        return entries.compactMap { entry in
            let haystack = entry.command
            guard haystack.contains(cmdBasename) || haystack.contains(command) else { return nil }
            if !needle.isEmpty, !haystack.contains(needle) { return nil }
            return entry.pid
        }
    }
}
