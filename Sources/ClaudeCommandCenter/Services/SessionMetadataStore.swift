import Foundation
import Combine

/// Persists per-session metadata (pin / tags / note / archived) to
/// `~/.claude/cc-center-meta.json`.
@MainActor
final class SessionMetadataStore: ObservableObject {
    static let shared = SessionMetadataStore()

    @Published private(set) var metadata: [String: SessionMetadata] = [:]

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = home.appending(path: ".claude/cc-center-meta.json")
        load()
    }

    // MARK: - Access

    func meta(for sessionId: String) -> SessionMetadata {
        metadata[sessionId] ?? SessionMetadata()
    }

    func update(_ sessionId: String, _ mutate: (inout SessionMetadata) -> Void) {
        var current = metadata[sessionId] ?? SessionMetadata()
        mutate(&current)
        current.updatedAt = .now
        metadata[sessionId] = current
        save()
    }

    func remove(_ sessionId: String) {
        metadata.removeValue(forKey: sessionId)
        save()
    }

    // MARK: - Tag helpers

    func togglePin(_ sessionId: String) {
        update(sessionId) { $0.pinned.toggle() }
    }

    func addTag(_ tag: String, to sessionId: String) {
        let t = normalize(tag)
        guard !t.isEmpty else { return }
        update(sessionId) { if !$0.tags.contains(t) { $0.tags.append(t) } }
    }

    func removeTag(_ tag: String, from sessionId: String) {
        update(sessionId) { $0.tags.removeAll { $0 == tag } }
    }

    func setNote(_ note: String, for sessionId: String) {
        update(sessionId) { $0.note = note }
    }

    func setArchived(_ archived: Bool, for sessionId: String) {
        update(sessionId) { $0.archived = archived }
    }

    /// Every tag that exists anywhere, sorted by frequency.
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for m in metadata.values {
            for t in m.tags { counts[t, default: 0] += 1 }
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }

    private func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? decoder.decode([String: SessionMetadata].self, from: data) else { return }
        metadata = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(metadata) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SessionMetadataStore save failed: \(error)")
        }
    }
}
