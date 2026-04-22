import Foundation

struct ClaudeProcess: Identifiable, Hashable, Sendable {
    let id: Int32  // PID
    var pid: Int32 { id }
    let executable: String
    let argsDisplay: String
    let cwd: String?
    let startedAt: Date
    let sessionId: String?     // resolved from `--resume <uuid>` if present
}
