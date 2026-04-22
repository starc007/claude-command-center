import Foundation

struct PortInfo: Identifiable, Hashable, Sendable {
    let id: String           // "\(pid)-\(port)-\(proto)"
    let port: Int
    let pid: Int32
    let processName: String
    let commandPath: String
    let family: ProcessFamily
    let netProtocol: String  // "TCP" / "TCPv6"
    let startedAt: Date?
    let user: String?
}

enum ProcessFamily: String, CaseIterable, Identifiable, Sendable {
    case node, python, docker, rust, go, ruby, java, database, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .node:     return "Node"
        case .python:   return "Python"
        case .docker:   return "Docker"
        case .rust:     return "Rust"
        case .go:       return "Go"
        case .ruby:     return "Ruby"
        case .java:     return "Java"
        case .database: return "Databases"
        case .other:    return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .node:     return "cube"
        case .python:   return "chevron.left.forwardslash.chevron.right"
        case .docker:   return "shippingbox"
        case .rust:     return "gearshape.2"
        case .go:       return "arrow.triangle.branch"
        case .ruby:     return "sparkles"
        case .java:     return "cup.and.saucer"
        case .database: return "cylinder.split.1x2"
        case .other:    return "terminal"
        }
    }

    static func from(processName name: String) -> ProcessFamily {
        let n = name.lowercased()
        if n.contains("node") || n.contains("bun") || n.contains("deno") { return .node }
        if n.contains("python") || n.contains("uvicorn") || n.contains("gunicorn") { return .python }
        if n.contains("docker") || n.contains("com.dock") || n.contains("colima") { return .docker }
        if n == "cargo" || n.contains("rustc") || n.hasSuffix("-rs") { return .rust }
        if n == "go" || n.contains("goland") { return .go }
        if n.contains("ruby") || n.contains("puma") || n.contains("rails") { return .ruby }
        if n.contains("java") || n.contains("kotlin") { return .java }
        if n.contains("postgres") || n.contains("mysql") || n.contains("redis") || n.contains("mongo") { return .database }
        return .other
    }
}
