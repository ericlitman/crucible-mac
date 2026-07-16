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
}
