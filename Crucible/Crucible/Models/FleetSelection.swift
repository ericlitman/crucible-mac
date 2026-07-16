import Foundation

enum FleetSelection: Hashable, Sendable {
    case host(hostID: String)
    case job(jobID: String)
    case lane(jobID: String, laneID: String)
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
                tokenBounds: nil,
                timeBounds: nil,
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
