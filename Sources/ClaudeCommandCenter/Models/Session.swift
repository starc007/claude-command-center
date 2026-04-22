import Foundation

struct ProjectSession: Identifiable, Hashable, Sendable {
    let id: String                 // folder name on disk
    let folderName: String         // raw folder name
    let projectPath: String        // resolved cwd ("/Users/…/my-repo")
    let displayName: String        // basename of projectPath
    let sessionCount: Int          // number of .jsonl files
    let messageCount: Int          // approximate across all sessions
    let lastActiveAt: Date?
    let inputTokens: Int
    let outputTokens: Int
}
