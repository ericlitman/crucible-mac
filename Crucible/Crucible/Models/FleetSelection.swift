import Foundation

enum FleetSelection: Hashable, Sendable {
    case host(hostID: String)
    case job(hostID: String, jobID: String)
    case lane(hostID: String, jobID: String, laneID: String)

    var hostID: String {
        switch self {
        case let .host(hostID), let .job(hostID, _), let .lane(hostID, _, _): hostID
        }
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
    let tokenUse: Int?
    let tokenBounds: TokenBounds?
    let timeBoundSeconds: TimeInterval?
    let sourceTimestamp: Date
}

extension FleetSnapshot {
    func detail(for selection: FleetSelection?) -> FleetSelectionDetail? {
        guard let selection, let host = host(id: selection.hostID) else { return nil }

        switch selection {
        case .host:
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
                timeBoundSeconds: nil,
                sourceTimestamp: sourceTimestamp
            )
        case let .job(_, jobID):
            guard let job = host.jobs.first(where: { $0.id == jobID }) else { return nil }
            return FleetSelectionDetail(
                eyebrow: "Job • \(host.displayName)",
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
                timeBoundSeconds: nil,
                sourceTimestamp: sourceTimestamp
            )
        case let .lane(_, jobID, laneID):
            guard
                let job = host.jobs.first(where: { $0.id == jobID }),
                let lane = job.lanes.first(where: { $0.id == laneID })
            else { return nil }
            return FleetSelectionDetail(
                eyebrow: "Lane • \(job.id) • \(host.displayName)",
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
                timeBoundSeconds: lane.timeBoundSeconds,
                sourceTimestamp: sourceTimestamp
            )
        }
    }
}
