import Foundation
import AppKit

/// Download + swap logic for self-updating. Handles only the mechanical bits
/// (HTTP download, zip extraction, handoff script, relaunch); orchestration
/// and state transitions live in UpdateChecker.
enum Updater {
    enum UpdaterError: Error, LocalizedError {
        case notRunningAsBundle
        case zipExtractionFailed
        case appNotFoundInZip
        case swapScriptFailed

        var errorDescription: String? {
            switch self {
            case .notRunningAsBundle:   return "Auto-update only works when launched from a .app bundle (not swift run)."
            case .zipExtractionFailed:  return "Could not extract the downloaded zip."
            case .appNotFoundInZip:     return "No .app bundle found inside the downloaded zip."
            case .swapScriptFailed:     return "Failed to start the install helper script."
            }
        }
    }

    /// Downloads the release zip to a temp dir and extracts it. Reports
    /// incremental progress 0…1 via the closure. Returns the staged .app URL.
    static func downloadAndStage(
        release: ReleaseInfo,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ClaudeCommandCenter-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipURL = tempDir.appending(path: "app.zip")

        // Stream with a delegate-less session. URLSession.download gives
        // a temp file URL; we track progress via the request's expected length.
        let (downloadedURL, _) = try await URLSession.shared.download(from: release.zipDownloadURL) { completed in
            Task { @MainActor in progress(completed) }
        }
        try FileManager.default.moveItem(at: downloadedURL, to: zipURL)
        progress(0.95)

        // Extract with ditto -x -k (macOS native, preserves resource forks).
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, tempDir.path]
        ditto.standardOutput = Pipe()
        ditto.standardError  = Pipe()
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdaterError.zipExtractionFailed }

        // Find the .app inside the extracted directory.
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdaterError.appNotFoundInZip
        }

        // Strip quarantine so Gatekeeper doesn't re-prompt after relaunch.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", appURL.path]
        xattr.standardOutput = Pipe()
        xattr.standardError  = Pipe()
        try? xattr.run()
        xattr.waitUntilExit()

        progress(1.0)
        return appURL
    }

    /// Writes a swap script to temp, spawns it detached, then quits the
    /// current app. The script waits for our PID to exit, replaces the
    /// installed .app, and relaunches.
    static func installAndRelaunch(stagedAppURL: URL) throws {
        guard let installedURL = Bundle.main.bundleURL.pathComponents.isEmpty
                ? nil
                : Bundle.main.bundleURL,
              installedURL.pathExtension == "app"
        else {
            throw UpdaterError.notRunningAsBundle
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "ccc-update-\(UUID().uuidString).sh")
        let myPID = ProcessInfo.processInfo.processIdentifier

        let script = #"""
        #!/bin/sh
        set -e
        PID="$1"
        STAGED="$2"
        INSTALLED="$3"

        # Wait up to 10s for the running app to exit.
        i=0
        while kill -0 "$PID" 2>/dev/null; do
            i=$((i+1))
            if [ $i -gt 50 ]; then break; fi
            sleep 0.2
        done

        # Move old app aside, then place staged in its slot.
        BACKUP="${INSTALLED%.app}.backup-$(date +%s).app"
        if [ -d "$INSTALLED" ]; then
            mv "$INSTALLED" "$BACKUP"
        fi
        mv "$STAGED" "$INSTALLED"
        xattr -dr com.apple.quarantine "$INSTALLED" 2>/dev/null || true

        # Relaunch. If relaunch succeeds, drop the backup after a beat.
        open "$INSTALLED"
        ( sleep 3; rm -rf "$BACKUP" ) &
        """#

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, "\(myPID)", stagedAppURL.path, installedURL.path]
        // Detach fully — we want the script to outlive this process.
        do {
            try process.run()
        } catch {
            throw UpdaterError.swapScriptFailed
        }

        // Give the swap script a moment to start polling, then exit cleanly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}

/// Small async download helper with incremental progress callback.
extension URLSession {
    func download(
        from url: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        let (stream, response) = try await bytes(from: url)
        let expected = response.expectedContentLength

        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "ccc-download-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    progress(min(0.95, Double(written) / Double(expected) * 0.95))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }

        return (tmp, response)
    }
}
