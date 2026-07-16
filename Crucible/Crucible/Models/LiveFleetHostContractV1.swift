import Foundation

nonisolated struct LiveFleetHostCapacityV1: Codable, Equatable, Sendable {
    let configuredLaneLimit: Int?
    let reportedLimit: Int?
    let active: Int?
    let queueDepth: Int?

    enum CodingKeys: String, CodingKey {
        case configuredLaneLimit = "configured_lane_limit"
        case reportedLimit = "reported_limit"
        case active
        case queueDepth = "queue_depth"
    }
}
nonisolated struct LiveFleetHostAlertV1: Codable, Equatable, Sendable {
    let type: String
    let severity: String
    let message: String?
}

nonisolated struct LiveFleetHostCountsV1: Codable, Equatable, Sendable {
    let active: Int?
    let terminal: Int?
    let total: Int?
    let byState: LiveFleetStateCountsV1

    enum CodingKeys: String, CodingKey {
        case active, terminal, total
        case byState = "by_state"
    }
}

nonisolated struct LiveFleetHostResourcesV1: Codable, Equatable, Sendable {
    let available: Bool
    let memoryHeadroomPercent: Double?
    let swapUsedPercent: Double?
    let swapUsedGigabytes: Double?
    let loadOneNormalized: Double?
    let runnerFraction: Double?
    let diskFreePercent: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case available, error
        case memoryHeadroomPercent = "mem_headroom_percent"
        case swapUsedPercent = "swap_used_percent"
        case swapUsedGigabytes = "swap_used_gigabytes"
        case loadOneNormalized = "load_one_normalized"
        case runnerFraction = "runner_fraction"
        case diskFreePercent = "disk_free_percent"
    }
}

nonisolated struct LiveFleetHostPressureV1: Codable, Equatable, Sendable {
    let state: String?
    let reason: String?
    let sampledAt: Date?

    enum CodingKeys: String, CodingKey {
        case state, reason
        case sampledAt = "sampled_at"
    }
}

nonisolated struct LiveFleetHostV1: Codable, Equatable, Sendable, Identifiable {
    enum Availability: String, Codable, Sendable { case available, unavailable }

    let id: String
    let address: String?
    let transport: String?
    let state: Availability
    let observedAt: Date?
    let capacity: LiveFleetHostCapacityV1
    let counts: LiveFleetHostCountsV1
    let jobsTruncated: Bool
    let resources: LiveFleetHostResourcesV1?
    let pressure: LiveFleetHostPressureV1?
    let alerts: [LiveFleetHostAlertV1]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, address, transport, state, capacity, counts, resources, pressure, alerts, error
        case observedAt = "observed_at"
        case jobsTruncated = "jobs_truncated"
    }
}

nonisolated struct LiveFleetHeartbeatV1: Codable, Equatable, Sendable {
    let state: String?
    let at: Date?
    let nextTickAt: Date?

    enum CodingKeys: String, CodingKey {
        case state, at
        case nextTickAt = "next_tick_at"
    }
}

nonisolated struct LiveFleetQueueV1: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let observedAt: Date?
    let heartbeat: LiveFleetHeartbeatV1?
    let counts: LiveFleetStateCountsV1
    let jobIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, heartbeat, counts
        case observedAt = "observed_at"
        case jobIDs = "job_ids"
    }
}
