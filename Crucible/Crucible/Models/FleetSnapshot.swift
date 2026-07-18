import Foundation

enum WorkState: String, CaseIterable, Hashable, Identifiable, Sendable {
    case active
    case waiting
    case completed
    case failed
    case blocked
    case stalled
    case unknown

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
        case .unknown: "questionmark.circle.fill"
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
    let soft: Double?
    let hard: Double?
}

struct TimeBounds: Hashable, Sendable {
    let softSeconds: TimeInterval?
    let hardSeconds: TimeInterval?
}

struct LaneSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: WorkState
    let currentStage: String?
    let elapsedSeconds: TimeInterval?
    let lastMeaningfulProgressAt: Date?
    let retryCount: Int?
    let restartCount: Int?
    let recoverableFailures: [String]
    let tokenUse: Double?
    let tokenBounds: TokenBounds
    let timeBounds: TimeBounds
}

struct JobSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let hostID: String?
    let title: String
    let state: WorkState
    let currentStage: String?
    let elapsedSeconds: TimeInterval?
    let lastMeaningfulProgressAt: Date?
    let retryCount: Int?
    let restartCount: Int?
    let recoverableFailures: [String]
    let tokenUse: Double?
    let tokenBounds: TokenBounds
    let timeBounds: TimeBounds
    let lanes: [LaneSnapshot]
}

struct HostSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let condition: HostCondition
    let activeLaneCount: Int?
    let laneCapacity: Int?
    /// The CLI supplied only part of this host's job detail (AC-7: truncation
    /// must be exposed, never presented as a confident empty host).
    let jobsTruncated: Bool
    let jobs: [JobSnapshot]

    init(
        id: String,
        displayName: String,
        condition: HostCondition,
        activeLaneCount: Int?,
        laneCapacity: Int?,
        jobsTruncated: Bool = false,
        jobs: [JobSnapshot]
    ) {
        self.id = id
        self.displayName = displayName
        self.condition = condition
        self.activeLaneCount = activeLaneCount
        self.laneCapacity = laneCapacity
        self.jobsTruncated = jobsTruncated
        self.jobs = jobs
    }

    /// Compact lane summary for tight rows; truncation is carried separately
    /// (glyph in narrow layouts, spelled out in `capacityLabel` for VoiceOver).
    var laneSummary: String {
        guard let activeLaneCount, let laneCapacity else { return "capacity unknown" }
        return "\(activeLaneCount)/\(laneCapacity) lanes"
    }

    var capacityLabel: String {
        jobsTruncated ? "\(laneSummary) · job detail truncated" : laneSummary
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
    let jobs: [JobSnapshot]
    let conditions: [FleetConditionSnapshot]
    private let contractStateCounts: [WorkState: Int]?

    init(
        contractVersion: String,
        sourceTimestamp: Date,
        queue: [QueueItemSnapshot],
        hosts: [HostSnapshot],
        jobs: [JobSnapshot]? = nil,
        conditions: [FleetConditionSnapshot] = [],
        stateCounts: [WorkState: Int]? = nil
    ) {
        self.contractVersion = contractVersion
        self.sourceTimestamp = sourceTimestamp
        self.queue = queue
        self.hosts = hosts
        let hostedJobs = hosts.flatMap(\.jobs)
        let suppliedJobs = jobs ?? []
        var seenJobIDs = Set<String>()
        self.jobs = (hostedJobs + suppliedJobs).filter { seenJobIDs.insert($0.id).inserted }
        self.conditions = conditions
        contractStateCounts = stateCounts
    }

    var stateCounts: [WorkState: Int] {
        if let contractStateCounts { return contractStateCounts }
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

    func job(id: String) -> JobSnapshot? {
        jobs.first { $0.id == id }
    }
}
