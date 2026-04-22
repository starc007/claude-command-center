import Foundation

struct UsageEvent: Hashable, Sendable {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let projectPath: String
    let sessionId: String

    var totalCost: Double { ModelPricing.cost(for: self) }
}

struct ProjectUsage: Identifiable, Hashable, Sendable {
    let id: String
    let projectPath: String
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let cost: Double
    let lastActiveAt: Date?
}

struct DailySpend: Identifiable, Hashable, Sendable {
    let id: Date
    let date: Date
    let cost: Double
}

/// Pricing is expressed in USD per 1,000,000 tokens. Values match Anthropic's
/// published rates as of early 2026 for the Claude 4.x family; tweak here if
/// they change.
enum ModelPricing {
    struct Rates {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    static let opus = Rates(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
    static let sonnet = Rates(input: 3.0, output: 15.0, cacheWrite: 3.75,  cacheRead: 0.30)
    static let haiku  = Rates(input: 1.0, output:  5.0, cacheWrite: 1.25,  cacheRead: 0.10)

    static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus")   { return opus }
        if m.contains("haiku")  { return haiku }
        return sonnet // default to Sonnet for unknown + any sonnet match
    }

    static func cost(for event: UsageEvent) -> Double {
        let r = rates(for: event.model)
        let inCost       = Double(event.inputTokens)       * r.input       / 1_000_000
        let outCost      = Double(event.outputTokens)      * r.output      / 1_000_000
        let cacheWrite   = Double(event.cacheCreateTokens) * r.cacheWrite  / 1_000_000
        let cacheRead    = Double(event.cacheReadTokens)   * r.cacheRead   / 1_000_000
        return inCost + outCost + cacheWrite + cacheRead
    }
}
