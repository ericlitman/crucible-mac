import Foundation

enum FleetSelection: Hashable, Sendable {
    case host(hostID: String)
    case job(jobID: String)
    case lane(jobID: String, laneID: String)
}

/// A selection whose entity cannot be resolved to detail in the current
/// snapshot. AC-7: the selection keeps its identity and a truthful
/// explanation instead of being silently replaced.
struct UnresolvedSelection: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// The entity's identity is in the current queue, but the CLI
        /// truncated its detail out of this snapshot.
        case detailTruncated
        /// The snapshot is partial; the entity may exist outside coverage.
        case partialSnapshot
        /// The snapshot is complete and the entity is not in it.
        case absent
    }

    let selection: FleetSelection
    let reason: Reason

    var kindLabel: String {
        switch selection {
        case .host: "host"
        case .job: "job"
        case .lane: "lane"
        }
    }

    var identityLabel: String {
        switch selection {
        case let .host(hostID): hostID
        case let .job(jobID): jobID
        case let .lane(jobID, laneID): "\(jobID) · \(laneID)"
        }
    }

    var explanation: String {
        switch reason {
        case .detailTruncated:
            if case .lane = selection {
                "The selected lane's job is in the current queue, but the CLI truncated the job's detail out of this snapshot. The selection is retained."
            } else {
                "This \(kindLabel) is in the current queue, but the CLI truncated its detail out of this snapshot. The selection is retained."
            }
        case .partialSnapshot:
            "This \(kindLabel) is not supplied in the current partial snapshot — it may still exist outside the snapshot's coverage. The selection is retained."
        case .absent:
            "This \(kindLabel) is not present in the current snapshot."
        }
    }
}

enum NotificationTargetUnavailableReason: Equatable, Sendable {
    case partialSnapshot
    case targetUnavailable
}

struct UnresolvedNotificationTarget: Equatable, Sendable {
    let route: FleetAlertRoute
    let reason: NotificationTargetUnavailableReason
}

struct NotificationNavigationRequest: Equatable, Sendable {
    let id: UUID
    let route: FleetAlertRoute

    init(route: FleetAlertRoute) {
        id = UUID()
        self.route = route
    }
}

struct FleetSelectionDetail: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let state: WorkState?
    let currentStage: String?
    let elapsedSeconds: TimeInterval?
    let lastMeaningfulProgressAt: Date?
    let retryCount: Int?
    let restartCount: Int?
    let recoverableFailures: [String]
    let tokenUse: Double?
    let tokenBounds: TokenBounds?
    let timeBounds: TimeBounds?
    let lanes: [LaneSnapshot]
    let conditions: [FleetConditionSnapshot]
    let sourceTimestamp: Date
}

protocol FleetRecoveryCountProviding {
    var retryCount: Int? { get }
    var restartCount: Int? { get }
}

extension FleetRecoveryCountProviding {
    var recoveryHistoryLabel: String? {
        let parts = [
            retryCount.map { countLabel($0, singular: "retry", plural: "retries") },
            restartCount.map { countLabel($0, singular: "restart", plural: "restarts") },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

extension FleetSelectionDetail: FleetRecoveryCountProviding {
    var hasMetrics: Bool {
        currentStage != nil
            || elapsedSeconds != nil
            || tokenUse != nil
            || timeBounds?.softSeconds != nil
            || timeBounds?.hardSeconds != nil
            || tokenBounds?.soft != nil
            || tokenBounds?.hard != nil
    }
}

extension LaneSnapshot: FleetRecoveryCountProviding {}

extension FleetSnapshot {
    func detail(for selection: FleetSelection?) -> FleetSelectionDetail? {
        guard let selection else { return nil }

        switch selection {
        case let .host(hostID):
            guard let host = host(id: hostID) else { return nil }
            return FleetSelectionDetail(
                eyebrow: "Host • \(host.condition.title)",
                title: host.displayName,
                state: nil,
                currentStage: nil,
                elapsedSeconds: nil,
                lastMeaningfulProgressAt: nil,
                retryCount: nil,
                restartCount: nil,
                recoverableFailures: [],
                tokenUse: nil,
                tokenBounds: nil,
                timeBounds: nil,
                lanes: [],
                conditions: conditions.filter { $0.hostID == hostID },
                sourceTimestamp: sourceTimestamp
            )
        case let .job(jobID):
            guard let job = job(id: jobID) else { return nil }
            let location = job.hostID ?? "Unassigned queue"
            return FleetSelectionDetail(
                eyebrow: "Job • \(location)",
                title: "\(job.id) · \(job.title)",
                state: job.state,
                currentStage: job.currentStage,
                elapsedSeconds: job.elapsedSeconds,
                lastMeaningfulProgressAt: job.lastMeaningfulProgressAt,
                retryCount: job.retryCount,
                restartCount: job.restartCount,
                recoverableFailures: job.recoverableFailures,
                tokenUse: job.tokenUse,
                tokenBounds: job.tokenBounds,
                timeBounds: job.timeBounds,
                lanes: job.lanes,
                conditions: conditions.filter { $0.jobID == jobID },
                sourceTimestamp: sourceTimestamp
            )
        case let .lane(jobID, laneID):
            guard
                let job = job(id: jobID),
                let lane = job.lanes.first(where: { $0.id == laneID })
            else { return nil }
            let location = job.hostID ?? "Unassigned"
            return FleetSelectionDetail(
                eyebrow: "Lane • \(job.id) • \(location)",
                title: lane.name,
                state: lane.state,
                currentStage: lane.currentStage,
                elapsedSeconds: lane.elapsedSeconds,
                lastMeaningfulProgressAt: lane.lastMeaningfulProgressAt,
                retryCount: lane.retryCount,
                restartCount: lane.restartCount,
                recoverableFailures: lane.recoverableFailures,
                tokenUse: lane.tokenUse,
                tokenBounds: lane.tokenBounds,
                timeBounds: lane.timeBounds,
                lanes: [],
                conditions: conditions.filter { $0.jobID == jobID && $0.laneID == laneID },
                sourceTimestamp: sourceTimestamp
            )
        }
    }
}
