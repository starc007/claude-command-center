import Foundation
import SwiftUI

struct SessionMetadata: Codable, Hashable, Sendable {
    var pinned: Bool = false
    var tags: [String] = []
    var note: String = ""
    var archived: Bool = false
    var updatedAt: Date = .now
}

struct TagStyle: Sendable, Hashable {
    let name: String
    let color: Color

    static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint,
        .teal, .cyan, .blue, .indigo, .purple, .pink
    ]

    /// Deterministic colour per tag name so the same tag looks the same
    /// everywhere without requiring persisted tag→colour mappings.
    static func color(for tag: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325  // FNV-1a
        for b in tag.lowercased().utf8 {
            hash ^= UInt64(b)
            hash &*= 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
