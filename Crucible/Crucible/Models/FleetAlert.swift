import Foundation

nonisolated struct FleetAlert: Equatable, Identifiable, Sendable {
    let episodeID: String
    let title: String
    let subtitle: String
    let body: String
    let hostID: String
    let jobID: String
    let laneID: String

    var id: String { episodeID }
}

enum ImportantConditionAlertPlanner {
    private enum ConditionKind: String {
        case noProgressStall = "no_progress_stall"
        case softTime = "time_soft_bound_exceeded"
        case hardTime = "time_hard_bound_exceeded"
        case softToken = "token_soft_bound_exceeded"
        case hardToken = "token_hard_bound_exceeded"
    }

    static func alerts(for snapshot: FleetSnapshot) -> [FleetAlert] {
        snapshot.conditions.compactMap(alert(for:))
    }

    private static func alert(for condition: FleetConditionSnapshot) -> FleetAlert? {
        guard let kind = ConditionKind(rawValue: condition.type),
              let hostID = condition.hostID,
              let jobID = condition.jobID,
              let laneID = condition.laneID else {
            return nil
        }

        return FleetAlert(
            episodeID: condition.id,
            title: title(for: kind),
            subtitle: "\(hostID) · \(jobID) · \(laneID)",
            body: body(for: kind, condition: condition),
            hostID: hostID,
            jobID: jobID,
            laneID: laneID
        )
    }

    private static func title(for kind: ConditionKind) -> String {
        switch kind {
        case .noProgressStall: "Lane stalled"
        case .softTime: "Soft time limit exceeded"
        case .hardTime: "Hard time limit exceeded"
        case .softToken: "Soft token limit exceeded"
        case .hardToken: "Hard token limit exceeded"
        }
    }

    private static func body(
        for kind: ConditionKind,
        condition: FleetConditionSnapshot
    ) -> String {
        let detail: String
        switch kind {
        case .noProgressStall:
            detail = durationDetail(
                actual: condition.actual,
                bound: condition.bound,
                prefix: "No meaningful progress for",
                limitLabel: "stall threshold"
            )
        case .softTime:
            detail = durationDetail(
                actual: condition.actual,
                bound: condition.bound,
                prefix: "Running for",
                limitLabel: "soft limit"
            )
        case .hardTime:
            detail = durationDetail(
                actual: condition.actual,
                bound: condition.bound,
                prefix: "Running for",
                limitLabel: "hard limit"
            )
        case .softToken:
            detail = tokenDetail(
                actual: condition.actual,
                bound: condition.bound,
                limitLabel: "soft limit"
            )
        case .hardToken:
            detail = tokenDetail(
                actual: condition.actual,
                bound: condition.bound,
                limitLabel: "hard limit"
            )
        }
        return "\(detail) Open Crucible to inspect this lane."
    }

    private static func durationDetail(
        actual: Double?,
        bound: Double?,
        prefix: String,
        limitLabel: String
    ) -> String {
        switch (actual, bound) {
        case let (.some(actual), .some(bound)):
            "\(prefix) \(formatDuration(actual)); \(limitLabel) is \(formatDuration(bound))."
        case let (.some(actual), nil):
            "\(prefix) \(formatDuration(actual))."
        default:
            "The CLI reports this lane beyond its \(limitLabel)."
        }
    }

    private static func tokenDetail(
        actual: Double?,
        bound: Double?,
        limitLabel: String
    ) -> String {
        switch (actual, bound) {
        case let (.some(actual), .some(bound)):
            "Used \(formatTokens(actual)) tokens; \(limitLabel) is \(formatTokens(bound))."
        case let (.some(actual), nil):
            "Used \(formatTokens(actual)) tokens."
        default:
            "The CLI reports this lane beyond its \(limitLabel)."
        }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private static func formatTokens(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
