import Foundation

enum MCPConfigWriter {
    enum WriteError: Error, LocalizedError {
        case invalidName
        case invalidCommand
        case fileUnreadable
        case fileUnwritable
        case serializationFailed
        case alreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .invalidName:          return "Name is required."
            case .invalidCommand:       return "Command is required."
            case .fileUnreadable:       return "Could not read the config file."
            case .fileUnwritable:       return "Could not write the config file."
            case .serializationFailed:  return "Could not serialize the config."
            case .alreadyExists(let n): return "A server named \(n) already exists."
            }
        }
    }

    static func add(
        source: MCPSource,
        name: String,
        command: String,
        args: [String],
        env: [String: String]
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCmd  = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw WriteError.invalidName }
        guard !trimmedCmd.isEmpty  else { throw WriteError.invalidCommand }

        let url = configURL(for: source)
        var root = try loadJSONObject(at: url)

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        if servers[trimmedName] != nil {
            throw WriteError.alreadyExists(trimmedName)
        }

        var entry: [String: Any] = ["command": trimmedCmd]
        if !args.isEmpty { entry["args"] = args }
        if !env.isEmpty  { entry["env"]  = env }

        servers[trimmedName] = entry
        root["mcpServers"] = servers

        try writeJSONObject(root, to: url)
    }

    // MARK: - Helpers

    private static func configURL(for source: MCPSource) -> URL {
        switch source {
        case .claudeCode:    return MCPManager.claudeCodeConfigPath
        case .claudeDesktop: return MCPManager.claudeDesktopConfigPath
        }
    }

    private static func loadJSONObject(at url: URL) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { throw WriteError.fileUnreadable }
        guard !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WriteError.fileUnreadable
        }
        return obj
    }

    private static func writeJSONObject(_ obj: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        // Ensure parent directory exists (Library/Application Support/Claude, e.g.)
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys]
        ) else { throw WriteError.serializationFailed }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WriteError.fileUnwritable
        }
    }
}
