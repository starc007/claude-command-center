import Foundation

/// Semantic version (major.minor.patch). Pre-release and build metadata are
/// stripped. Missing components default to 0. `v` prefix is tolerated.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Strip pre-release / metadata: "1.2.3-beta+abc" -> "1.2.3"
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }

        let parts = s.split(separator: ".").map(String.init)
        guard !parts.isEmpty,
              let major = Int(parts[0])
        else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        self.patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }
    var tagName: String { "v\(description)" }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Reads the currently-running bundle's short version string.
    /// Returns 0.0.0 for SPM dev runs without a bundle.
    static var current: AppVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return AppVersion(raw) ?? AppVersion(major: 0)
    }
}

struct ReleaseInfo: Hashable, Sendable {
    let version: AppVersion
    let tagName: String
    let releaseURL: URL
    let zipDownloadURL: URL
    let publishedAt: Date?
    let body: String
}
