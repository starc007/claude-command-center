import Foundation
import AppKit

enum SessionExporter {
    static func exportSession(_ session: Session) {
        let md = renderHeader(for: session) + renderSession(at: session.jsonlURL)
        let suggested = "\(session.projectName)-\(session.id.prefix(8)).md"
        promptSaveAndWrite(markdown: md, suggestedName: suggested)
    }

    // MARK: - Markdown rendering

    private static func renderHeader(for session: Session) -> String {
        var out = ""
        out += "# \(session.projectName)\n\n"
        out += "- **Path**: `\(session.projectPath)`\n"
        out += "- **Session**: `\(session.id)`\n"
        out += "- **Last active**: \(formatted(date: session.lastActiveAt))\n\n"
        out += "---\n\n"
        return out
    }

    private static func renderSession(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return "" }

        var md = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            guard let type = obj["type"] as? String else { continue }
            switch type {
            case "user":      md += renderUserEntry(obj) + "\n"
            case "assistant": md += renderAssistantEntry(obj) + "\n"
            default: continue
            }
        }
        return md
    }

    private static func renderUserEntry(_ obj: [String: Any]) -> String {
        guard let message = obj["message"] as? [String: Any] else { return "" }
        let text = extractText(from: message["content"])
        guard !text.isEmpty else { return "" }
        return "### User\n\n> " + text.replacingOccurrences(of: "\n", with: "\n> ") + "\n"
    }

    private static func renderAssistantEntry(_ obj: [String: Any]) -> String {
        guard let message = obj["message"] as? [String: Any] else { return "" }
        var pieces: [String] = ["### Assistant"]

        if let content = message["content"] as? [[String: Any]] {
            for block in content {
                guard let type = block["type"] as? String else { continue }
                switch type {
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty { pieces.append(t) }
                case "tool_use":
                    let name = (block["name"] as? String) ?? "tool"
                    let input = (block["input"] as? [String: Any]) ?? [:]
                    pieces.append("<details><summary>🛠 `\(name)`</summary>\n\n```json\n\(prettyJSON(input))\n```\n\n</details>")
                default: continue
                }
            }
        }
        return pieces.joined(separator: "\n\n") + "\n"
    }

    private static func extractText(from content: Any?) -> String {
        if let str = content as? String { return str }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { ($0["text"] as? String) }.joined(separator: "\n")
        }
        return ""
    }

    private static func prettyJSON(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: - Save panel

    private static func promptSaveAndWrite(markdown: String, suggestedName: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private static func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
