import Foundation

/// Moves sessions to an archive folder or deletes them outright. The archive
/// folder is a real directory on disk (`~/.claude/projects/_archive/`) so
/// nothing lives in metadata alone — users can still read the JSONL later.
enum SessionArchiver {
    static let archiveRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects/_archive", directoryHint: .isDirectory)
    }()

    static func archive(_ sessions: [Session]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: archiveRoot, withIntermediateDirectories: true)

        for session in sessions {
            let dest = archiveRoot.appending(path: "\(session.folderName)__\(session.id).jsonl")
            do {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: session.jsonlURL, to: dest)
            } catch {
                NSLog("archive failed for \(session.id): \(error)")
            }
        }
    }

    static func delete(_ sessions: [Session]) {
        let fm = FileManager.default
        for session in sessions {
            do {
                try fm.removeItem(at: session.jsonlURL)
            } catch {
                NSLog("delete failed for \(session.id): \(error)")
            }
        }
    }
}
