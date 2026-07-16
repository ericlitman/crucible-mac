import Foundation

nonisolated enum LiveFleetDelivery: Equatable, Sendable {
    case snapshot(LiveFleetSnapshotV1)
    case error(LiveFleetErrorEnvelopeV1)
}

nonisolated enum LiveFleetWireState: String, Codable, Sendable {
    case active, waiting, completed, failed, blocked, stalled, unknown

    @MainActor var presentationState: WorkState {
        WorkState(rawValue: rawValue) ?? .unknown
    }
}

nonisolated enum LiveFleetFreshnessState: String, Codable, Sendable {
    case fresh, stale
}

nonisolated enum LiveFleetCompletenessState: String, Codable, Sendable {
    case complete, partial
}

nonisolated struct LiveFleetFreshnessV1: Codable, Equatable, Sendable {
    let state: LiveFleetFreshnessState
    let ageSeconds: Double?
    let staleAfterSeconds: Double

    enum CodingKeys: String, CodingKey {
        case state
        case ageSeconds = "age_seconds"
        case staleAfterSeconds = "stale_after_seconds"
    }
}

nonisolated struct LiveFleetHostCoverageV1: Codable, Equatable, Sendable {
    let expected: Int
    let observed: Int
    let available: Int
}

nonisolated struct LiveFleetCompletenessV1: Codable, Equatable, Sendable {
    let state: LiveFleetCompletenessState
    let reasons: [String]
    let hostCoverage: LiveFleetHostCoverageV1
    let jobsTruncated: Bool

    enum CodingKeys: String, CodingKey {
        case state, reasons
        case hostCoverage = "host_coverage"
        case jobsTruncated = "jobs_truncated"
    }
}

nonisolated struct LiveFleetSnapshotV1: Codable, Equatable, Sendable {
    let schema: String
    let contractVersion: Int
    let generatedAt: Date
    let sourceObservedAt: Date?
    let controllerGeneration: String?
    let freshness: LiveFleetFreshnessV1
    let completeness: LiveFleetCompletenessV1
    let sources: LiveFleetSourcesV1
    let counts: LiveFleetSnapshotCountsV1
    let hosts: [LiveFleetHostV1]
    let queues: [LiveFleetQueueV1]
    let jobs: [LiveFleetJobV1]
    let conditions: [LiveFleetConditionV1]

    enum CodingKeys: String, CodingKey {
        case schema, freshness, completeness, sources, counts, hosts, queues, jobs, conditions
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
        case sourceObservedAt = "source_observed_at"
        case controllerGeneration = "controller_generation"
    }

    @MainActor func presentationSnapshot() -> FleetSnapshot {
        let presentationJobs = jobs.map(\.presentationSnapshot)
        let jobsByID = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        let queuedJobIDs = queues.flatMap(\.jobIDs).uniqued()
        let queueItems = queuedJobIDs.map { jobID in
            let job = jobsByID[jobID]
            return QueueItemSnapshot(
                id: jobID,
                title: job?.title ?? "Details unavailable",
                hostID: job?.hostID,
                state: job?.state.presentationState ?? .unknown
            )
        }
        let hostSnapshots = hosts.map { host in
            let hostJobs = presentationJobs.filter { $0.hostID == host.id }
            let condition: HostCondition
            if host.state == .unavailable {
                condition = .offline
            } else if host.error != nil || !host.alerts.isEmpty {
                condition = .degraded
            } else if (host.capacity.active ?? 0) > 0 {
                condition = .busy
            } else {
                condition = .available
            }
            return HostSnapshot(
                id: host.id,
                displayName: host.id,
                condition: condition,
                activeLaneCount: host.capacity.active,
                laneCapacity: host.capacity.configuredLaneLimit ?? host.capacity.reportedLimit,
                jobs: hostJobs
            )
        }

        return FleetSnapshot(
            contractVersion: String(contractVersion),
            sourceTimestamp: sourceObservedAt ?? generatedAt,
            queue: queueItems,
            hosts: hostSnapshots,
            jobs: presentationJobs,
            conditions: conditions.map(\.presentationSnapshot),
            stateCounts: counts.jobs.counts.presentationCounts
        )
    }
}

nonisolated struct LiveFleetErrorV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case unavailable, incompatible, failed }

    let code: String
    let kind: Kind
    let message: String
    let retryable: Bool
    let source: String?
}

nonisolated struct LiveFleetErrorEnvelopeV1: Codable, Equatable, Sendable {
    let schema: String
    let contractVersion: Int?
    let generatedAt: Date
    let error: LiveFleetErrorV1

    enum CodingKeys: String, CodingKey {
        case schema, error
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
    }
}

@MainActor private extension LiveFleetJobV1 {
    var presentationSnapshot: JobSnapshot {
        JobSnapshot(
            id: id,
            hostID: hostID,
            title: title,
            state: state.presentationState,
            currentStage: nil,
            elapsedSeconds: nil,
            lastMeaningfulProgressAt: nil,
            retryCount: attempts.retries,
            restartCount: attempts.restarts,
            recoverableFailures: failures.filter { $0.recoverable == true }.map(\.type),
            tokenUse: nil,
            tokenBounds: TokenBounds(soft: bounds.tokens.soft, hard: bounds.tokens.hard),
            timeBounds: TimeBounds(
                softSeconds: bounds.time.softSeconds,
                hardSeconds: bounds.time.hardSeconds
            ),
            lanes: lanes.map(\.presentationSnapshot)
        )
    }
}

@MainActor private extension LiveFleetConditionV1 {
    var presentationSnapshot: FleetConditionSnapshot {
        FleetConditionSnapshot(
            id: id,
            type: type,
            severity: severity.presentationSeverity,
            hostID: affected.hostID,
            jobID: affected.jobID,
            laneID: affected.laneID,
            firstObservedAt: firstObservedAt,
            lastObservedAt: lastObservedAt,
            actual: actual,
            bound: bound,
            action: action
        )
    }
}

@MainActor private extension LiveFleetConditionV1.Severity {
    var presentationSeverity: FleetConditionSeverity {
        switch self {
        case .info: .info
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
    }
}

@MainActor private extension LiveFleetLaneV1 {
    var presentationSnapshot: LaneSnapshot {
        LaneSnapshot(
            id: id,
            name: stage.displayName ?? id,
            state: state.presentationState,
            currentStage: stage.displayName,
            elapsedSeconds: progress.elapsedSeconds,
            lastMeaningfulProgressAt: progress.lastMeaningfulAt,
            retryCount: attempts.retries,
            restartCount: attempts.restarts,
            recoverableFailures: failures.filter { $0.recoverable == true }.map(\.type),
            tokenUse: usage.available ? usage.tokens?.total : nil,
            tokenBounds: TokenBounds(soft: bounds.tokens.soft, hard: bounds.tokens.hard),
            timeBounds: TimeBounds(
                softSeconds: bounds.time.softSeconds,
                hardSeconds: bounds.time.hardSeconds
            )
        )
    }
}

private nonisolated extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
