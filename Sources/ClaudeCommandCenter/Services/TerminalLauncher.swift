import Foundation
import AppKit

enum TerminalLauncher {
    /// Opens Terminal.app (or iTerm if installed) in the given directory and
    /// runs `claude --continue`.
    static func resumeClaude(at path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escaped)\\" && claude --continue"
        end tell
        """
        runAppleScript(script)
    }

    /// Opens Terminal.app at the given directory with no command preloaded.
    static func openTerminal(at path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escaped)\\""
        end tell
        """
        runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("TerminalLauncher AppleScript error: \(errorInfo)")
        }
    }
}
