import Foundation
import AppKit

enum TerminalLauncher {
    enum Kind {
        case ghostty
        case iterm
        case terminal
    }

    /// Detects whichever terminal is installed, preferring Ghostty → iTerm → Terminal.
    static func preferred() -> Kind {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Applications/Ghostty.app") { return .ghostty }
        if fm.fileExists(atPath: "/Applications/iTerm.app")   { return .iterm }
        return .terminal
    }

    /// Resumes a specific Claude Code session by its UUID.
    static func resumeSession(id: String, cwd: String) {
        let command = "cd \(shellQuote(cwd)) && claude --resume \(id)"
        run(command: command)
    }

    /// Continues whichever session was last active in the project directory.
    static func resumeClaude(at path: String) {
        let command = "cd \(shellQuote(path)) && claude --continue"
        run(command: command)
    }

    static func openTerminal(at path: String) {
        run(command: "cd \(shellQuote(path))")
    }

    // MARK: - Dispatch

    private static func run(command: String) {
        switch preferred() {
        case .ghostty:  runGhostty(command: command)
        case .iterm:    runITerm(command: command)
        case .terminal: runAppleTerminal(command: command)
        }
    }

    private static func runGhostty(command: String) {
        // `open -na Ghostty --args -e sh -c <command>` — each token is a
        // separate argument. Ghostty's -e executes the rest as argv, so we
        // hand it `sh -c <command>` to evaluate our `cd && claude …` line.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-na", "Ghostty", "--args", "-e", "sh", "-c", command]
        do { try task.run() } catch {
            runAppleTerminal(command: command)
        }
    }

    private static func runITerm(command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                tell current window to create tab with default profile
            end if
            tell current session of current window
                write text "\(escaped)"
            end tell
        end tell
        """
        runAppleScript(script)
    }

    private static func runAppleTerminal(command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Helpers

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("TerminalLauncher AppleScript error: \(errorInfo)")
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func shellJoin(_ args: [String]) -> String {
        args.map { shellQuote($0) }.joined(separator: " ")
    }
}
