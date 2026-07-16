import Foundation

nonisolated struct LiveFleetStateCountsV1: Codable, Equatable, Sendable {
    let active: Int
    let waiting: Int
    let completed: Int
    let failed: Int
    let blocked: Int
    let stalled: Int
    let unknown: Int

    var presentationCounts: [WorkState: Int] {
        [
            .active: active, .waiting: waiting, .completed: completed,
            .failed: failed, .blocked: blocked, .stalled: stalled, .unknown: unknown,
        ]
    }
}
nonisolated struct LiveFleetStateCountsWithTotalV1: Codable, Equatable, Sendable {
    let total: Int
    let active: Int
    let waiting: Int
    let completed: Int
    let failed: Int
    let blocked: Int
    let stalled: Int
    let unknown: Int

    var counts: LiveFleetStateCountsV1 {
        LiveFleetStateCountsV1(
            active: active, waiting: waiting, completed: completed, failed: failed,
            blocked: blocked, stalled: stalled, unknown: unknown
        )
    }
}

nonisolated struct LiveFleetSourceV1: Codable, Equatable, Sendable {
    let path: String
    let observedAt: Date?
    let schema: String?

    enum CodingKeys: String, CodingKey {
        case path, schema
        case observedAt = "observed_at"
    }
}

nonisolated struct LiveFleetRefreshV1: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case fresh, cached }
    enum Status: String, Codable, Sendable { case cached, freshCache = "fresh_cache", fresh, partial, failed }

    let mode: Mode
    let attempted: Bool
    let status: Status
    let durationMilliseconds: Int
    let coalesced: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case mode, attempted, status, coalesced, error
        case durationMilliseconds = "duration_ms"
    }
}

nonisolated struct LiveFleetMonitorSourceV1: Codable, Equatable, Sendable {
    let path: String
    let observedAt: Date?
    let schema: String?
    let refresh: LiveFleetRefreshV1

    enum CodingKeys: String, CodingKey {
        case path, schema, refresh
        case observedAt = "observed_at"
    }
}

nonisolated struct LiveFleetSourcesV1: Codable, Equatable, Sendable {
    let queue: LiveFleetSourceV1
    let monitor: LiveFleetMonitorSourceV1
    let capacity: LiveFleetSourceV1
}

nonisolated struct LiveFleetSnapshotCountsV1: Codable, Equatable, Sendable {
    let hosts: Int
    let queues: Int
    let jobs: LiveFleetStateCountsWithTotalV1
    let lanes: LiveFleetStateCountsWithTotalV1
    let conditions: Int
}
