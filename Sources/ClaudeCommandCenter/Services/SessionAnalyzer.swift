import Foundation

struct SessionAnalytics: Sendable, Hashable {
    let sessionId: String
    let model: String?
    let firstAt: Date?
    let lastAt: Date?
    let messageCount: Int
    let inputTokens: Int
    let outputTokens: Int

    var duration: TimeInterval? {
        guard let first = firstAt, let last = lastAt, last > first else { return nil }
        return last.timeIntervalSince(first)
    }

    var shortModel: String {
        guard let m = model?.lowercased() else { return "—" }
        if m.contains("opus")  { return "opus"  }
        if m.contains("haiku") { return "haiku" }
        if m.contains("sonnet") { return "sonnet" }
        return m
    }
}

/// Reads a JSONL once per session to extract duration and dominant model.
/// Results are cached in-process per `sessionId` + file size so repeated
/// list refreshes don't re-parse multi-MB files.
@MainActor
final class SessionAnalyzer {
    static let shared = SessionAnalyzer()

    private var cache: [String: (fileSize: UInt64, value: SessionAnalytics)] = [:]

    func analytics(for session: Session) -> SessionAnalytics? {
        if let hit = cache[session.id], hit.fileSize == session.fileSize {
            return hit.value
        }
        return nil
    }

    /// Analyzes many sessions off the main actor, writing results back into
    /// the cache. Call from a Task.
    func preload(_ sessions: [Session]) async {
        let needed = sessions.filter { session in
            if let hit = cache[session.id] { return hit.fileSize != session.fileSize }
            return true
        }
        guard !needed.isEmpty else { return }

        let results = await Task.detached(priority: .utility) { () -> [(String, UInt64, SessionAnalytics)] in
            var out: [(String, UInt64, SessionAnalytics)] = []
            for s in needed {
                let a = Self.analyze(session: s)
                out.append((s.id, s.fileSize, a))
            }
            return out
        }.value

        for (id, size, value) in results {
            cache[id] = (size, value)
        }
        // Nudge SwiftUI subscribers by posting on the MainActor — analytics()
        // is synchronous but not observed; views pull via `id` in onReceive.
        NotificationCenter.default.post(name: .sessionAnalyticsUpdated, object: nil)
    }

    // MARK: - Parsing

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated private static func analyze(session: Session) -> SessionAnalytics {
        guard let data = try? Data(contentsOf: session.jsonlURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return SessionAnalytics(
                sessionId: session.id, model: nil,
                firstAt: nil, lastAt: nil,
                messageCount: 0, inputTokens: 0, outputTokens: 0
            )
        }

        var firstAt: Date?
        var lastAt: Date?
        var modelCounts: [String: Int] = [:]
        var msgs = 0
        var input = 0
        var output = 0

        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = obj["type"] as? String
            if let ts = obj["timestamp"] as? String, let date = parseDate(ts) {
                if firstAt == nil || date < firstAt! { firstAt = date }
                if lastAt  == nil || date > lastAt!  { lastAt  = date }
            }
            if type == "user" || type == "assistant" { msgs += 1 }
            if type == "assistant", let message = obj["message"] as? [String: Any] {
                if let m = message["model"] as? String {
                    modelCounts[m, default: 0] += 1
                }
                if let usage = message["usage"] as? [String: Any] {
                    input  += (usage["input_tokens"]  as? Int) ?? 0
                    output += (usage["output_tokens"] as? Int) ?? 0
                }
            }
        }

        let model = modelCounts.max { $0.value < $1.value }?.key
        return SessionAnalytics(
            sessionId: session.id, model: model,
            firstAt: firstAt, lastAt: lastAt,
            messageCount: msgs,
            inputTokens: input, outputTokens: output
        )
    }

    nonisolated private static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoFrac.date(from: s)
    }
}

extension Notification.Name {
    static let sessionAnalyticsUpdated = Notification.Name("SessionAnalyticsUpdated")
}
