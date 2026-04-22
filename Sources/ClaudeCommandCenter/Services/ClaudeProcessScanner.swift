import Foundation
import Darwin

enum ClaudeProcessScanner {
    static func scan() -> [ClaudeProcess] {
        guard let out = runCommand(
            executable: "/bin/ps",
            args: ["-axww", "-o", "pid=,etime=,command="]
        ) else { return [] }

        var procs: [ClaudeProcess] = []
        for raw in out.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let parsed = parsePsLine(String(raw)) else { continue }
            guard isClaudeCLI(executable: parsed.executable) else { continue }

            let started = Date(timeIntervalSinceNow: -parsed.etimeSeconds)
            let cwd = cwd(for: parsed.pid)
            let sessionId = extractSessionId(fromArgs: parsed.args)
            let argsDisplay = parsed.args.joined(separator: " ")

            procs.append(ClaudeProcess(
                id: parsed.pid,
                executable: parsed.executable,
                argsDisplay: argsDisplay,
                cwd: cwd,
                startedAt: started,
                sessionId: sessionId
            ))
        }
        return procs.sorted { $0.startedAt > $1.startedAt }
    }

    static func kill(pid: Int32, hard: Bool = false) {
        _ = Darwin.kill(pid, hard ? SIGKILL : SIGTERM)
    }

    // MARK: - Parsing

    private struct PSLine {
        let pid: Int32
        let etimeSeconds: TimeInterval
        let executable: String
        let args: [String]
    }

    private static func parsePsLine(_ line: String) -> PSLine? {
        let trimmed = line.drop(while: { $0 == " " })
        // "<pid> <etime> <command...>"
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3,
              let pid = Int32(parts[0])
        else { return nil }

        let etime = parseEtime(String(parts[1]))
        let commandLine = String(parts[2])
        let tokens = commandLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let head = tokens.first else { return nil }

        return PSLine(
            pid: pid,
            etimeSeconds: etime,
            executable: head,
            args: Array(tokens.dropFirst())
        )
    }

    /// `ps -o etime` outputs `[[dd-]hh:]mm:ss`.
    private static func parseEtime(_ s: String) -> TimeInterval {
        var days: Double = 0
        var rest = s
        if let dash = rest.firstIndex(of: "-") {
            days = Double(rest[..<dash]) ?? 0
            rest = String(rest[rest.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").map { Double($0) ?? 0 }
        let hms: Double
        switch parts.count {
        case 3: hms = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: hms =                   parts[0] * 60 + parts[1]
        case 1: hms =                                   parts[0]
        default: hms = 0
        }
        return days * 86400 + hms
    }

    private static func isClaudeCLI(executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        // Match the binary literally called `claude`, avoid plugin scripts named `claude-*.cjs`.
        return last == "claude"
    }

    private static func extractSessionId(fromArgs args: [String]) -> String? {
        guard let i = args.firstIndex(of: "--resume"), i + 1 < args.count else { return nil }
        let candidate = args[i + 1]
        // UUID sanity check.
        guard candidate.count == 36, candidate.contains("-") else { return nil }
        return candidate
    }

    private static func cwd(for pid: Int32) -> String? {
        guard let out = runCommand(
            executable: "/usr/sbin/lsof",
            args: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        ) else { return nil }
        // lsof -Fn prints lines beginning with `n` for the pathname.
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.first == "n" { return String(line.dropFirst()) }
        }
        return nil
    }

    // MARK: - Process spawn helper

    private static func runCommand(executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
