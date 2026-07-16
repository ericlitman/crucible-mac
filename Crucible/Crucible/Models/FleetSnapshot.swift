import Foundation

enum WorkState: String, CaseIterable, Hashable, Identifiable, Sendable {
    case active
    case waiting
    case completed
    case failed
    case blocked
    case stalled

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .active: "play.circle.fill"
        case .waiting: "clock.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .blocked: "hand.raised.circle.fill"
        case .stalled: "exclamationmark.octagon.fill"
        }
    }
}

enum HostCondition: String, Hashable, Sendable {
    case available
    case busy
    case degraded
    case offline

    var title: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle"
        case .busy: "gearshape.2"
        case .degraded: "exclamationmark.triangle"
        case .offline: "wifi.slash"
        }
    }
}

struct TokenBounds: Hashable, Sendable {
    let soft: Int?
    let hard: Int?
}

struct LaneSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: WorkState
    let currentStage: String
    let elapsedSeconds: TimeInterval
    let lastMeaningfulProgressAt: Date?
    let retryCount: Int
    let restartCount: Int
    let recoverableFailures: [String]
    let tokenUse: Int
    let tokenBounds: TokenBounds
    let timeBoundSeconds: TimeInterval?
}

struct JobSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let state: WorkState
    let currentStage: String
    let elapsedSeconds: TimeInterval
    let lastMeaningfulProgressAt: Date?
    let retryCount: Int
    let restartCount: Int
    let recoverableFailures: [String]
    let tokenUse: Int
    let lanes: [LaneSnapshot]
}

struct HostSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let condition: HostCondition
    let activeLaneCount: Int
    let laneCapacity: Int
    let jobs: [JobSnapshot]

    var capacityLabel: String {
        "\(activeLaneCount)/\(laneCapacity) lanes"
    }
}

struct QueueItemSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let hostID: String?
    let state: WorkState
}

struct FleetSnapshot: Hashable, Sendable {
    let contractVersion: String
    let sourceTimestamp: Date
    let queue: [QueueItemSnapshot]
    let hosts: [HostSnapshot]

    var stateCounts: [WorkState: Int] {
        var result = Dictionary(uniqueKeysWithValues: WorkState.allCases.map { ($0, 0) })
        for item in queue {
            result[item.state, default: 0] += 1
        }
        return result
    }

    func count(for state: WorkState) -> Int {
        stateCounts[state, default: 0]
    }

    func host(id: String?) -> HostSnapshot? {
        guard let id else { return nil }
        return hosts.first { $0.id == id }
    }
}
