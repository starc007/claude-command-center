import Foundation
import AppKit

enum SessionExporter {
    /// Renders every JSONL in a project folder as a combined markdown transcript.
    static func exportProject(_ project: ProjectSession) {
        let folder = SessionReader.projectsRoot.appending(path: project.folderName, directoryHint: .isDirectory)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let jsonlFiles = files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !jsonlFiles.isEmpty else { return }

        let markdown = renderMarkdown(for: project, from: jsonlFiles)
        promptSaveAndWrite(markdown: markdown, suggestedName: suggestedFilename(for: project))
    }

    // MARK: - Markdown rendering

    private static func renderMarkdown(for project: ProjectSession, from files: [URL]) -> String {
        var out = ""
        out += "# \(project.displayName)\n\n"
        out += "- **Project path**: `\(project.projectPath)`\n"
        if let last = project.lastActiveAt {
            out += "- **Last active**: \(formatted(date: last))\n"
        }
        out += "- **Sessions**: \(project.sessionCount)\n"
        out += "- **Messages**: \(project.messageCount)\n"
        out += "- **Tokens**: \(project.inputTokens) in · \(project.outputTokens) out\n\n"
        out += "---\n\n"

        for file in files {
            out += renderSession(at: file)
            out += "\n---\n\n"
        }
        return out
    }

    private static func renderSession(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return "" }

        var md = "## Session `\(url.deletingPathExtension().lastPathComponent)`\n\n"

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            guard let type = obj["type"] as? String else { continue }
            switch type {
            case "user":
                md += renderUserEntry(obj) + "\n"
            case "assistant":
                md += renderAssistantEntry(obj) + "\n"
            default:
                continue
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
        var pieces: [String] = []
        pieces.append("### Assistant")

        if let content = message["content"] as? [[String: Any]] {
            for block in content {
                guard let type = block["type"] as? String else { continue }
                switch type {
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty {
                        pieces.append(t)
                    }
                case "tool_use":
                    let name = (block["name"] as? String) ?? "tool"
                    let input = (block["input"] as? [String: Any]) ?? [:]
                    let inputJSON = prettyJSON(input)
                    pieces.append("<details><summary>🛠 `\(name)`</summary>\n\n```json\n\(inputJSON)\n```\n\n</details>")
                default:
                    continue
                }
            }
        } else if let text = extractTextFromPlain(message["content"]) {
            pieces.append(text)
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

    private static func extractTextFromPlain(_ content: Any?) -> String? {
        if let str = content as? String { return str }
        return nil
    }

    private static func prettyJSON(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }

    // MARK: - Save panel

    private static func suggestedFilename(for project: ProjectSession) -> String {
        let stamp = Self.fileStampFormatter.string(from: .now)
        return "\(project.displayName)-\(stamp).md"
    }

    private static func promptSaveAndWrite(markdown: String, suggestedName: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
