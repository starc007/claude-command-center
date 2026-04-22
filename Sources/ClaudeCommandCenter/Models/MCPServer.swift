import Foundation

enum MCPSource: String, Sendable {
    case claudeCode    = "Claude Code"
    case claudeDesktop = "Claude Desktop"
}

struct MCPServer: Identifiable, Hashable, Sendable {
    let id: String  // "\(source.rawValue)::\(name)"
    let name: String
    let command: String
    let args: [String]
    let envKeys: [String]
    let source: MCPSource
    let pids: [Int32]

    var isRunning: Bool { !pids.isEmpty }

    var displayCommand: String {
        ([command] + args).joined(separator: " ")
    }
}
