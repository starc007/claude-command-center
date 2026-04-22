import Foundation

/// One entry per JSONL file on disk — a single Claude Code session.
struct Session: Identifiable, Hashable, Sendable {
    let id: String                 // session UUID (JSONL basename)
    let folderName: String         // parent folder on disk
    let projectPath: String        // resolved cwd
    let projectName: String        // basename of projectPath
    let jsonlURL: URL
    let lastActiveAt: Date
    let fileSize: UInt64
}

/// Used for the old project-level grouping if we ever need it back.
struct ProjectSummary: Identifiable, Hashable, Sendable {
    let id: String                 // folder name
    let projectPath: String
    let projectName: String
    let sessionCount: Int
    let lastActiveAt: Date?
}
