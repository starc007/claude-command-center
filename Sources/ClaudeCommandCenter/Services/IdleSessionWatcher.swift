import Foundation

/// Polls every N seconds for JSONL modifications under `~/.claude/projects/`,
/// keeps a per-project activity model, and fires a notification when a
/// project transitions from "actively writing" to "idle for >= idleThreshold".
///
/// Notifications require a bundled `.app` (see NotificationService); running
/// via `swift run` the watcher still does its bookkeeping but delivery is
/// silently dropped.
@MainActor
final class IdleSessionWatcher {
    static let shared = IdleSessionWatcher()

    private var timer: Timer?
    private var latestMtime: [String: Date] = [:]   // projectFolder -> latest mtime seen
    private var activeSince: [String: Date] = [:]   // projectFolder -> when we first noticed activity
    private var notifiedIdle: Set<String> = []      // projectFolder -> already fired idle notification

    private let pollInterval: TimeInterval
    private let idleThreshold: TimeInterval
    private let minActivityDuration: TimeInterval

    init(
        pollInterval: TimeInterval = 15,
        idleThreshold: TimeInterval = 45,
        minActivityDuration: TimeInterval = 30
    ) {
        self.pollInterval = pollInterval
        self.idleThreshold = idleThreshold
        self.minActivityDuration = minActivityDuration
    }

    func start() {
        timer?.invalidate()
        // Prime the state so we don't fire for sessions that were already idle at launch.
        tick(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(initial: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick

    private func tick(initial: Bool) {
        let fresh = collectMtimes()
        let now = Date()

        for (folder, newMtime) in fresh {
            let previous = latestMtime[folder]
            latestMtime[folder] = newMtime

            let movedForward = previous.map { newMtime > $0 } ?? false
            let recentlyMoved = now.timeIntervalSince(newMtime) < idleThreshold

            if recentlyMoved {
                // Still actively writing.
                if activeSince[folder] == nil { activeSince[folder] = newMtime }
                notifiedIdle.remove(folder)
                continue
            }

            // Idle now. Did it have enough activity to warrant a notification?
            guard !initial,
                  let activityStart = activeSince[folder],
                  newMtime.timeIntervalSince(activityStart) >= minActivityDuration,
                  !notifiedIdle.contains(folder),
                  movedForward == false  // only after we've observed it stop moving
            else {
                if !recentlyMoved { activeSince.removeValue(forKey: folder) }
                continue
            }

            let projectName = displayName(for: folder)
            NotificationService.notify(
                title: "Claude finished working",
                body: "No new activity in \(projectName) for \(Int(idleThreshold))s."
            )
            notifiedIdle.insert(folder)
            activeSince.removeValue(forKey: folder)
        }
    }

    // MARK: - Helpers

    private func collectMtimes() -> [String: Date] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: SessionReader.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var out: [String: Date] = [:]
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var latest: Date?
            for file in files where file.pathExtension == "jsonl" {
                if let m = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    if latest == nil || m > latest! { latest = m }
                }
            }
            if let latest { out[folder.lastPathComponent] = latest }
        }
        return out
    }

    private func displayName(for folderName: String) -> String {
        // Best-effort: decode the folder name. The real path is lossy for paths
        // with hyphens; we just want something readable in a notification.
        let decoded = folderName.hasPrefix("-")
            ? String(folderName.dropFirst()).replacingOccurrences(of: "-", with: "/")
            : folderName
        return URL(fileURLWithPath: decoded).lastPathComponent
    }
}
