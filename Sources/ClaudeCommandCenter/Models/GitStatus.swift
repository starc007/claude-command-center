import Foundation

struct GitStatus: Hashable, Sendable {
    let branch: String?
    let modifiedCount: Int
    let untrackedCount: Int
    let lastCommitSubject: String?

    var hasChanges: Bool { modifiedCount + untrackedCount > 0 }

    var summary: String {
        if let branch { return branch }
        return "—"
    }
}
