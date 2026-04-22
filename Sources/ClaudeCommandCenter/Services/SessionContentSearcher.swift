import Foundation

enum SessionContentSearcher {
    /// Returns the folder names of projects that have at least one JSONL line
    /// containing `query` (case-insensitive) in a user/assistant message body.
    /// Runs off the main actor.
    static func folderIdsMatching(query: String) -> Set<String> {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }

        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: SessionReader.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var matches: Set<String> = []
        for folder in folders {
            if contains(query: q, in: folder) {
                matches.insert(folder.lastPathComponent)
            }
        }
        return matches
    }

    private static func contains(query: String, in projectFolder: URL) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: projectFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
        for url in jsonlFiles {
            // Cheap pass: lowercase the whole file and look for the substring.
            // JSONL files can be multi-MB, so avoid full JSON parsing on the
            // hot path — we only need "does this project mention X?".
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               text.lowercased().contains(query) {
                return true
            }
        }
        return false
    }
}
