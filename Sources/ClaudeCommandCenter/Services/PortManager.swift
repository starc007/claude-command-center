import Foundation
import Darwin

enum PortManager {
    /// Fetches all TCP ports currently in LISTEN state.
    static func listListeningPorts() -> [PortInfo] {
        guard let lsof = runCommand(
            executable: "/usr/sbin/lsof",
            args: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcntu"]
        ) else { return [] }

        let entries = parseLsofOutput(lsof)
        return entries
            .sorted { $0.port < $1.port }
    }

    static func kill(pid: Int32, hard: Bool = false) {
        let sig: Int32 = hard ? SIGKILL : SIGTERM
        _ = Darwin.kill(pid, sig)
    }

    // MARK: - lsof parsing

    /// lsof -F outputs records with one field per line, each prefixed by a
    /// single letter: p=pid, c=command, u=user, n=name (host:port), t=type, …
    /// Records are separated by a `p` line that starts a new process block.
    private static func parseLsofOutput(_ text: String) -> [PortInfo] {
        var out: [PortInfo] = []

        var pid: Int32 = 0
        var command: String = ""
        var user: String = ""

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let prefix = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch prefix {
            case "p":
                pid = Int32(value) ?? 0
                command = ""
                user = ""
            case "c":
                command = value
            case "u":
                user = value
            case "n":
                // e.g. "*:3000", "127.0.0.1:5432", "[::1]:8080"
                guard let port = extractPort(from: value) else { continue }
                let family = ProcessFamily.from(processName: command)
                let started = processStartTime(pid: pid)
                let commandPath = processPath(pid: pid) ?? command

                let info = PortInfo(
                    id: "\(pid)-\(port)-TCP",
                    port: port,
                    pid: pid,
                    processName: command,
                    commandPath: commandPath,
                    family: family,
                    netProtocol: "TCP",
                    startedAt: started,
                    user: user.isEmpty ? nil : user
                )
                out.append(info)
            default:
                continue
            }
        }
        return out
    }

    private static func extractPort(from addr: String) -> Int? {
        guard let colon = addr.lastIndex(of: ":") else { return nil }
        let portStr = addr[addr.index(after: colon)...]
        return Int(portStr)
    }

    // MARK: - Process info helpers

    private static func processStartTime(pid: Int32) -> Date? {
        guard let out = runCommand(
            executable: "/bin/ps",
            args: ["-o", "lstart=", "-p", "\(pid)"]
        ) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: trimmed)
    }

    private static func processPath(pid: Int32) -> String? {
        runCommand(executable: "/bin/ps", args: ["-o", "command=", "-p", "\(pid)"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Process spawning

    private static func runCommand(executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
