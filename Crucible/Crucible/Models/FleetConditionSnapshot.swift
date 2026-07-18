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

    /// Exact CLI condition-type vocabulary. `type` is an unconstrained wire
    /// string, so classification matches known values exactly — substring
    /// heuristics misfire (e.g. "install_failed" contains "stall").
    private static let stallTypes: Set<String> = ["stalled", "no_progress_stall"]
    private static let timeBoundTypes: Set<String> = ["time_soft_bound_exceeded", "time_hard_bound_exceeded"]
    private static let tokenBoundTypes: Set<String> = ["token_soft_bound_exceeded", "token_hard_bound_exceeded"]
    private static let staleTypes: Set<String> = ["source_stale"]

    /// The unit of `actual`/`bound`: stall/time/stale types carry seconds,
    /// token bounds carry tokens. Unknown types stay unitless rather than
    /// guessing.
    var measuresDuration: Bool {
        Self.stallTypes.contains(type) || Self.timeBoundTypes.contains(type) || Self.staleTypes.contains(type)
    }

    var measuresTokens: Bool {
        Self.tokenBoundTypes.contains(type)
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
        if Self.stallTypes.contains(type) { return .noRecentProgress }
        if Self.tokenBoundTypes.contains(type) { return .overTokens }
        if Self.timeBoundTypes.contains(type) { return .overTime }
        switch severity {
        case .critical, .error: return .failure
        case .warning, .info: return .advisory
        }
    }
}
