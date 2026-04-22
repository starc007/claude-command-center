import Foundation

enum GitService {
    static func status(at path: String) -> GitStatus? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }

        // Fast reject: no .git folder/file → not a repo.
        let gitMarker = (path as NSString).appendingPathComponent(".git")
        guard fm.fileExists(atPath: gitMarker) else { return nil }

        let branch = run("git", args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var modified = 0
        var untracked = 0
        if let porcelain = run("git", args: ["status", "--porcelain=v1"], cwd: path) {
            for line in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
                if line.hasPrefix("??") { untracked += 1 } else { modified += 1 }
            }
        }

        let lastSubject = run("git", args: ["log", "-1", "--format=%s"], cwd: path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return GitStatus(
            branch: branch?.isEmpty == false ? branch : nil,
            modifiedCount: modified,
            untrackedCount: untracked,
            lastCommitSubject: lastSubject?.isEmpty == false ? lastSubject : nil
        )
    }

    @discardableResult
    private static func run(_ tool: String, args: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
