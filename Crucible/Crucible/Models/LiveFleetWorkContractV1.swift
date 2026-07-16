import Foundation

nonisolated struct LiveFleetAttemptsV1: Codable, Equatable, Sendable {
    let current: String?
    let total: Int?
    let retries: Int?
    let restarts: Int?
    let retryLimit: Int?
    let history: [LiveFleetAttemptHistoryV1]
    let recoveries: [LiveFleetRecoveryV1]

    enum CodingKeys: String, CodingKey {
        case current, total, retries, restarts, history, recoveries
        case retryLimit = "retry_limit"
    }
}
nonisolated struct LiveFleetAttemptHistoryV1: Codable, Equatable, Sendable {
    let attemptID: String?
    let state: String?
    let endedAt: Date?
    let failureType: String?

    enum CodingKeys: String, CodingKey {
        case state
        case attemptID = "attempt_id"
        case endedAt = "ended_at"
        case failureType = "failure_type"
    }
}

nonisolated struct LiveFleetRecoveryV1: Codable, Equatable, Sendable {
    let at: Date?
    let continuation: String?
    let reason: String?
}

nonisolated struct LiveFleetFailureV1: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let type: String
    let occurredAt: Date?
    let recoverable: Bool?
    let recoveryAction: String?
    let evidenceAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, recoverable
        case occurredAt = "occurred_at"
        case recoveryAction = "recovery_action"
        case evidenceAvailable = "evidence_available"
    }
}

nonisolated struct LiveFleetTimeBoundsV1: Codable, Equatable, Sendable {
    let softSeconds: Double?
    let hardSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case softSeconds = "soft_seconds"
        case hardSeconds = "hard_seconds"
    }
}

nonisolated struct LiveFleetTokenBoundsV1: Codable, Equatable, Sendable {
    let soft: Double?
    let hard: Double?
}

nonisolated struct LiveFleetBoundsV1: Codable, Equatable, Sendable {
    let time: LiveFleetTimeBoundsV1
    let tokens: LiveFleetTokenBoundsV1
}

nonisolated struct LiveFleetTokenCountsV1: Codable, Equatable, Sendable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?
    let reasoningOutput: Double?
    let total: Double?

    enum CodingKeys: String, CodingKey {
        case input, output, total
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case reasoningOutput = "reasoning_output"
    }
}

nonisolated struct LiveFleetUsageV1: Codable, Equatable, Sendable {
    let available: Bool
    let source: String
    let observedAt: Date?
    let measurementQuality: String?
    let tokens: LiveFleetTokenCountsV1?

    enum CodingKeys: String, CodingKey {
        case available, source, tokens
        case observedAt = "observed_at"
        case measurementQuality = "measurement_quality"
    }
}

nonisolated struct LiveFleetStageV1: Codable, Equatable, Sendable {
    let id: String?
    let role: String?
    let phase: String?

    var displayName: String? { role ?? id ?? phase }
}

nonisolated struct LiveFleetProgressV1: Codable, Equatable, Sendable {
    enum SemanticSource: String, Codable, Sendable {
        case schedulerProgressTransition = "scheduler_progress_transition"
        case bestAvailableTransition = "best_available_transition"
        case hostMonitorTransition = "host_monitor_transition"
        case unavailable
    }

    let state: String?
    let message: String?
    let startedAt: Date?
    let lastObservedAt: Date?
    let lastMeaningfulAt: Date?
    let semanticSource: SemanticSource
    let elapsedSeconds: Double?
    let noProgressBoundSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case state, message
        case startedAt = "started_at"
        case lastObservedAt = "last_observed_at"
        case lastMeaningfulAt = "last_meaningful_at"
        case semanticSource = "semantic_source"
        case elapsedSeconds = "elapsed_seconds"
        case noProgressBoundSeconds = "no_progress_bound_seconds"
    }
}

nonisolated struct LiveFleetLifecycleV1: Codable, Equatable, Sendable {
    let terminal: Bool
}

nonisolated struct LiveFleetTimestampsV1: Codable, Equatable, Sendable {
    let createdAt: Date?
    let updatedAt: Date?
    let lastTransitionAt: Date?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastTransitionAt = "last_transition_at"
    }
}

nonisolated struct LiveFleetProvenanceV1: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case supervisorQueue = "supervisor_queue", hostMonitor = "host_monitor" }

    let source: Source
    let sourceID: String
    let runDirectory: String?
    let detailReasons: [String]

    enum CodingKeys: String, CodingKey {
        case source
        case sourceID = "source_id"
        case runDirectory = "run_dir"
        case detailReasons = "detail_reasons"
    }
}

nonisolated struct LiveFleetLaneV1: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let jobID: String
    let runID: String?
    let itemID: String?
    let stage: LiveFleetStageV1
    let model: String?
    let hostID: String?
    let state: LiveFleetWireState
    let rawState: String?
    let progress: LiveFleetProgressV1
    let attempts: LiveFleetAttemptsV1
    let failures: [LiveFleetFailureV1]
    let usage: LiveFleetUsageV1
    let bounds: LiveFleetBoundsV1

    enum CodingKeys: String, CodingKey {
        case id, stage, model, state, progress, attempts, failures, usage, bounds
        case jobID = "job_id"
        case runID = "run_id"
        case itemID = "item_id"
        case hostID = "host_id"
        case rawState = "raw_state"
    }
}

nonisolated struct LiveFleetJobV1: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let queueID: String?
    let runID: String?
    let title: String
    let issueIDs: [String]
    let hostID: String?
    let state: LiveFleetWireState
    let rawState: String?
    let lifecycle: LiveFleetLifecycleV1
    let timestamps: LiveFleetTimestampsV1
    let attempts: LiveFleetAttemptsV1
    let failures: [LiveFleetFailureV1]
    let bounds: LiveFleetBoundsV1
    let lanes: [LiveFleetLaneV1]
    let provenance: LiveFleetProvenanceV1

    enum CodingKeys: String, CodingKey {
        case id, title, state, lifecycle, timestamps, attempts, failures, bounds, lanes, provenance
        case queueID = "queue_id"
        case runID = "run_id"
        case issueIDs = "issue_ids"
        case hostID = "host_id"
        case rawState = "raw_state"
    }
}

nonisolated struct LiveFleetAffectedV1: Codable, Equatable, Sendable {
    let hostID: String?
    let jobID: String?
    let laneID: String?

    enum CodingKeys: String, CodingKey {
        case hostID = "host_id"
        case jobID = "job_id"
        case laneID = "lane_id"
    }
}

nonisolated struct LiveFleetConditionV1: Codable, Equatable, Sendable, Identifiable {
    enum Severity: String, Codable, Sendable { case info, warning, error, critical }

    let id: String
    let type: String
    let affected: LiveFleetAffectedV1
    let firstObservedAt: Date
    let lastObservedAt: Date
    let severity: Severity
    let actual: Double?
    let bound: Double?
    let action: String?

    enum CodingKeys: String, CodingKey {
        case id, type, affected, severity, actual, bound, action
        case firstObservedAt = "first_observed_at"
        case lastObservedAt = "last_observed_at"
    }
}
