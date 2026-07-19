import Foundation

nonisolated struct FleetAlert: Equatable, Identifiable, Sendable {
    let episodeID: String
    let conditionType: String
    let title: String
    let subtitle: String
    let body: String
    let hostID: String
    let jobID: String
    let laneID: String
    let sourceTimestamp: Date

    var id: String { episodeID }

    var route: FleetAlertRoute {
        FleetAlertRoute(
            conditionEpisodeID: episodeID,
            conditionType: conditionType,
            hostID: hostID,
            jobID: jobID,
            laneID: laneID,
            sourceTimestamp: sourceTimestamp
        )
    }

    func notificationPayload() -> NotificationPayload {
        NotificationPayload(
            episodeID: episodeID,
            requestIdentifier: "condition:\(episodeID)",
            title: title,
            subtitle: subtitle,
            body: body,
            userInfo: route.userInfo
        )
    }
}

nonisolated struct FleetAlertRoute: Equatable, Sendable {
    let conditionEpisodeID: String
    let conditionType: String
    let hostID: String
    let jobID: String
    let laneID: String
    let sourceTimestamp: Date

    private enum Key {
        static let conditionEpisodeID = "condition_episode_id"
        static let conditionType = "condition_type"
        static let hostID = "host_id"
        static let jobID = "job_id"
        static let laneID = "lane_id"
        static let sourceTimestamp = "source_timestamp"
    }

    var userInfo: [String: String] {
        [
            Key.conditionEpisodeID: conditionEpisodeID,
            Key.conditionType: conditionType,
            Key.hostID: hostID,
            Key.jobID: jobID,
            Key.laneID: laneID,
            Key.sourceTimestamp: String(sourceTimestamp.timeIntervalSince1970),
        ]
    }

    init(
        conditionEpisodeID: String,
        conditionType: String,
        hostID: String,
        jobID: String,
        laneID: String,
        sourceTimestamp: Date
    ) {
        self.conditionEpisodeID = conditionEpisodeID
        self.conditionType = conditionType
        self.hostID = hostID
        self.jobID = jobID
        self.laneID = laneID
        self.sourceTimestamp = sourceTimestamp
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let conditionEpisodeID = userInfo[Key.conditionEpisodeID] as? String,
              let conditionType = userInfo[Key.conditionType] as? String,
              let hostID = userInfo[Key.hostID] as? String,
              let jobID = userInfo[Key.jobID] as? String,
              let laneID = userInfo[Key.laneID] as? String,
              let timestamp = Self.timestamp(from: userInfo[Key.sourceTimestamp]) else {
            return nil
        }
        self.init(
            conditionEpisodeID: conditionEpisodeID,
            conditionType: conditionType,
            hostID: hostID,
            jobID: jobID,
            laneID: laneID,
            sourceTimestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private static func timestamp(from value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }
}

enum ImportantConditionAlertPlanner {
    private enum ConditionKind: String {
        case stalled = "stalled"
        case legacyNoProgressStall = "no_progress_stall"
        case softTime = "time_soft_bound_exceeded"
        case hardTime = "time_hard_bound_exceeded"
        case softToken = "token_soft_bound_exceeded"
        case hardToken = "token_hard_bound_exceeded"
    }

    static func alerts(for snapshot: FleetSnapshot) -> [FleetAlert] {
        snapshot.conditions.compactMap { alert(for: $0, in: snapshot) }
    }

    private static func alert(
        for condition: FleetConditionSnapshot,
        in snapshot: FleetSnapshot
    ) -> FleetAlert? {
        guard let kind = ConditionKind(rawValue: condition.type),
              let hostID = condition.hostID,
              let jobID = condition.jobID,
              let laneID = condition.laneID else {
            return nil
        }
        let job = snapshot.job(id: jobID)
        let laneName = job?.lanes.first(where: { $0.id == laneID })?.name ?? laneID
        let laneLabel = laneName == laneID ? laneID : "\(laneName) (\(laneID))"
        let jobLabel = job?.title ?? "Job \(jobID)"

        return FleetAlert(
            episodeID: condition.id,
            conditionType: condition.type,
            title: "\(title(for: kind)) · \(jobID)",
            subtitle: "\(jobLabel) · \(hostID)",
            body: "\(laneLabel): \(body(for: kind, condition: condition)) Source \(sourceLabel(snapshot.sourceTimestamp)).",
            hostID: hostID,
            jobID: jobID,
            laneID: laneID,
            sourceTimestamp: snapshot.sourceTimestamp
        )
    }

    private static func title(for kind: ConditionKind) -> String {
        switch kind {
        case .stalled, .legacyNoProgressStall: "Lane stalled"
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
        case .stalled, .legacyNoProgressStall:
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
        return detail
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

    private static func sourceLabel(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
