import Foundation

enum FleetConditionSeverity: String, Hashable, Sendable {
    case info, warning, error, critical
}

struct FleetConditionSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let type: String
    let severity: FleetConditionSeverity
    let hostID: String?
    let jobID: String?
    let laneID: String?
    let firstObservedAt: Date
    let lastObservedAt: Date
    let actual: Double?
    let bound: Double?
    let action: String?

    var title: String {
        type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var affectedLabel: String {
        [hostID, jobID, laneID].compactMap { $0 }.joined(separator: " · ")
    }

    /// The unit of `actual`/`bound`, derived from the CLI condition type
    /// vocabulary: time_*_bound_exceeded, stall conditions, and *stale carry
    /// seconds; token_*_bound_exceeded carries tokens. Unknown types stay
    /// unitless rather than guessing.
    var measuresDuration: Bool {
        type.contains("time") || type.contains("stall") || type.contains("stale")
    }

    var measuresTokens: Bool {
        type.contains("token")
    }

    func formattedMeasure(_ value: Double) -> String {
        if measuresDuration { return FleetFormat.duration(value) }
        if measuresTokens { return "\(FleetFormat.tokens(value)) tokens" }
        return value.formatted()
    }

    /// Presentation class for a condition. The CLI cannot yet distinguish
    /// "clearly dead" from "working quietly past a threshold", so red is
    /// reserved for critical severity and non-threshold error types; stall
    /// and bound crossings present as prominent amber with their own glyphs.
    enum PresentationClass {
        case overTime
        case overTokens
        case noRecentProgress
        case failure
        case advisory
    }

    var presentationClass: PresentationClass {
        if type.contains("stall") { return .noRecentProgress }
        if measuresTokens, type.contains("bound") { return .overTokens }
        if measuresDuration, type.contains("bound") { return .overTime }
        switch severity {
        case .critical, .error: return .failure
        case .warning, .info: return .advisory
        }
    }
}
