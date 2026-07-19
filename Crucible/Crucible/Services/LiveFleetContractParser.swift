import Foundation

nonisolated enum LiveFleetContractError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSON(String)
    case duplicateKey(String)
    case schemaViolation(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(detail): "The CLI returned invalid JSON: \(detail)"
        case let .duplicateKey(path): "The CLI returned a duplicate JSON key at \(path)."
        case let .schemaViolation(detail): "The CLI response does not match live-fleet v1: \(detail)"
        }
    }
}

nonisolated enum LiveFleetContractParser {
    static func parse(_ data: Data) throws -> LiveFleetDelivery {
        var duplicateScanner = JSONDuplicateKeyScanner(data: data)
        try duplicateScanner.validate()

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LiveFleetContractError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any], let schema = root["schema"] as? String else {
            throw LiveFleetContractError.schemaViolation("top-level object and schema are required")
        }

        let decoder = makeDecoder()
        switch schema {
        case "crucible.live-fleet.snapshot.v1":
            try LiveFleetContractShapeV1.validateSnapshot(root)
            let snapshot = try decode(LiveFleetSnapshotV1.self, from: data, using: decoder)
            guard snapshot.contractVersion == 1 else {
                throw LiveFleetContractError.schemaViolation("snapshot contract_version must be 1")
            }
            try validateSemantics(snapshot)
            return .snapshot(snapshot)
        case "crucible.live-fleet.error.v1":
            try LiveFleetContractShapeV1.validateError(root)
            return .error(try decode(LiveFleetErrorEnvelopeV1.self, from: data, using: decoder))
        default:
            throw LiveFleetContractError.schemaViolation("unsupported schema \(schema)")
        }
    }

    static func parseEvents(_ data: Data) throws -> LiveFleetEventsDelivery {
        var duplicateScanner = JSONDuplicateKeyScanner(data: data)
        try duplicateScanner.validate()

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LiveFleetContractError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any], let schema = root["schema"] as? String else {
            throw LiveFleetContractError.schemaViolation("top-level object and schema are required")
        }

        let decoder = makeDecoder()
        switch schema {
        case "crucible.live-fleet.events.v1":
            try LiveFleetContractShapeV1.validateEvents(root)
            let envelope = try decode(LiveFleetEventsEnvelopeV1.self, from: data, using: decoder)
            guard envelope.contractVersion == 1 else {
                throw LiveFleetContractError.schemaViolation("events contract_version must be 1")
            }
            try validateSemantics(envelope)
            return .events(envelope)
        case "crucible.live-fleet.error.v1":
            try LiveFleetContractShapeV1.validateError(root)
            let envelope = try decode(LiveFleetErrorEnvelopeV1.self, from: data, using: decoder)
            guard envelope.contractVersion == 1 else {
                throw LiveFleetContractError.schemaViolation("events error contract_version must be 1")
            }
            return .error(envelope)
        default:
            throw LiveFleetContractError.schemaViolation("unsupported schema \(schema)")
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "invalid RFC 3339 timestamp"
            )
        }
        return decoder
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LiveFleetContractError.schemaViolation(error.localizedDescription)
        }
    }

    private static func validateSemantics(_ snapshot: LiveFleetSnapshotV1) throws {
        try requireNonnegative(snapshot.freshness.ageSeconds, at: "freshness.age_seconds")
        try requireNonnegative(snapshot.freshness.staleAfterSeconds, at: "freshness.stale_after_seconds")
        try requireNonnegative(snapshot.completeness.hostCoverage.expected, at: "host_coverage.expected")
        try requireNonnegative(snapshot.completeness.hostCoverage.observed, at: "host_coverage.observed")
        try requireNonnegative(snapshot.completeness.hostCoverage.available, at: "host_coverage.available")
        try requireNonnegative(snapshot.sources.monitor.refresh.durationMilliseconds, at: "monitor.refresh.duration_ms")
        try requireNonnegative(snapshot.counts.hosts, at: "counts.hosts")
        try requireNonnegative(snapshot.counts.queues, at: "counts.queues")
        try requireNonnegative(snapshot.counts.conditions, at: "counts.conditions")
        try validate(snapshot.counts.jobs, at: "counts.jobs")
        try validate(snapshot.counts.lanes, at: "counts.lanes")
        guard snapshot.completeness.hostCoverage.available <= snapshot.completeness.hostCoverage.observed,
              snapshot.completeness.hostCoverage.observed <= snapshot.completeness.hostCoverage.expected
        else {
            throw LiveFleetContractError.schemaViolation("host coverage must satisfy available <= observed <= expected")
        }
        try requireUnique(snapshot.hosts.map(\.id), label: "host id")
        try requireUnique(snapshot.queues.map(\.id), label: "queue id")
        try requireUnique(snapshot.jobs.map(\.id), label: "job id")
        try requireUnique(snapshot.conditions.map(\.id), label: "condition id")

        let hostIDs = Set(snapshot.hosts.map(\.id))
        let jobsByID = Dictionary(uniqueKeysWithValues: snapshot.jobs.map { ($0.id, $0) })
        for host in snapshot.hosts {
            try requireNonnegative(host.capacity.configuredLaneLimit, at: "host \(host.id) capacity.configured_lane_limit")
            try requireNonnegative(host.capacity.reportedLimit, at: "host \(host.id) capacity.reported_limit")
            try requireNonnegative(host.capacity.active, at: "host \(host.id) capacity.active")
            try requireNonnegative(host.capacity.queueDepth, at: "host \(host.id) capacity.queue_depth")
            try requireNonnegative(host.counts.active, at: "host \(host.id) counts.active")
            try requireNonnegative(host.counts.terminal, at: "host \(host.id) counts.terminal")
            try requireNonnegative(host.counts.total, at: "host \(host.id) counts.total")
            try validate(host.counts.byState, at: "host \(host.id) counts.by_state")
            if let resources = host.resources {
                try validate(resources, hostID: host.id)
            }
        }
        var queuedJobIDs: [String] = []
        for queue in snapshot.queues {
            try validate(queue.counts, at: "queue \(queue.id) counts")
            queuedJobIDs.append(contentsOf: queue.jobIDs)
        }
        try requireUnique(queuedJobIDs, label: "queued job reference")
        if !snapshot.completeness.jobsTruncated {
            for jobID in queuedJobIDs where jobsByID[jobID] == nil {
                throw LiveFleetContractError.schemaViolation("queue references missing job \(jobID)")
            }
        }

        for job in snapshot.jobs {
            if let hostID = job.hostID, !hostIDs.contains(hostID) {
                throw LiveFleetContractError.schemaViolation("job \(job.id) references missing host \(hostID)")
            }
            try requireUnique(job.lanes.map(\.id), label: "lane id in job \(job.id)")
            try validate(job.attempts, at: "job \(job.id) attempts")
            try validate(job.bounds, at: "job \(job.id) bounds")
            for lane in job.lanes {
                guard lane.jobID == job.id else {
                    throw LiveFleetContractError.schemaViolation("lane \(lane.id) has mismatched job_id")
                }
                if let hostID = lane.hostID, !hostIDs.contains(hostID) {
                    throw LiveFleetContractError.schemaViolation("lane \(lane.id) references missing host \(hostID)")
                }
                try validate(lane, jobID: job.id)
            }
        }

        for condition in snapshot.conditions {
            if let hostID = condition.affected.hostID, !hostIDs.contains(hostID) {
                throw LiveFleetContractError.schemaViolation("condition \(condition.id) references missing host")
            }
            if let jobID = condition.affected.jobID,
               jobsByID[jobID] == nil,
               !snapshot.completeness.jobsTruncated {
                throw LiveFleetContractError.schemaViolation("condition \(condition.id) references missing job")
            }
            try requireNonnegative(condition.actual, at: "condition \(condition.id) actual")
            try requireNonnegative(condition.bound, at: "condition \(condition.id) bound")
        }
    }

    private static func validateSemantics(_ envelope: LiveFleetEventsEnvelopeV1) throws {
        try requireNonnegative(envelope.cursor.seq, at: "cursor.seq")
        var previousSequence = 0
        var eventIDs: Set<String> = []
        for event in envelope.events {
            guard event.schema == "crucible.live-fleet.transition.v1" else {
                throw LiveFleetContractError.schemaViolation("event \(event.id) has an unsupported schema")
            }
            guard event.seq > previousSequence else {
                throw LiveFleetContractError.schemaViolation("event seq values must be strictly increasing")
            }
            guard event.seq <= envelope.cursor.seq else {
                throw LiveFleetContractError.schemaViolation("event seq cannot exceed cursor.seq")
            }
            guard eventIDs.insert(event.id).inserted else {
                throw LiveFleetContractError.schemaViolation("duplicate event id: \(event.id)")
            }
            previousSequence = event.seq
        }
    }

    private static func validate(_ lane: LiveFleetLaneV1, jobID: String) throws {
        try requireNonnegative(lane.progress.elapsedSeconds, at: "lane \(jobID)/\(lane.id) elapsed_seconds")
        try requireNonnegative(lane.progress.noProgressBoundSeconds, at: "lane \(jobID)/\(lane.id) no_progress_bound_seconds")
        try validate(lane.bounds, at: "lane \(jobID)/\(lane.id) bounds")
        try validate(lane.attempts, at: "lane \(jobID)/\(lane.id) attempts")
        if let tokens = lane.usage.tokens {
            for (label, value) in [
                ("input", tokens.input), ("output", tokens.output), ("cache_read", tokens.cacheRead),
                ("cache_write", tokens.cacheWrite), ("reasoning_output", tokens.reasoningOutput),
                ("total", tokens.total),
            ] {
                try requireNonnegative(value, at: "lane \(jobID)/\(lane.id) token \(label)")
            }
        }
    }

    private static func validate(_ resources: LiveFleetHostResourcesV1, hostID: String) throws {
        for (label, value) in [
            ("mem_headroom_percent", resources.memoryHeadroomPercent),
            ("swap_used_percent", resources.swapUsedPercent),
            ("swap_used_gigabytes", resources.swapUsedGigabytes),
            ("load_one_normalized", resources.loadOneNormalized),
            ("runner_fraction", resources.runnerFraction),
            ("disk_free_percent", resources.diskFreePercent),
        ] {
            try requireNonnegative(value, at: "host \(hostID) resources.\(label)")
        }
    }

    private static func validate(_ attempts: LiveFleetAttemptsV1, at path: String) throws {
        try requireNonnegative(attempts.total, at: "\(path).total")
        try requireNonnegative(attempts.retries, at: "\(path).retries")
        try requireNonnegative(attempts.restarts, at: "\(path).restarts")
        try requireNonnegative(attempts.retryLimit, at: "\(path).retry_limit")
    }

    private static func validate(_ bounds: LiveFleetBoundsV1, at path: String) throws {
        try requireNonnegative(bounds.time.softSeconds, at: "\(path).time.soft_seconds")
        try requireNonnegative(bounds.time.hardSeconds, at: "\(path).time.hard_seconds")
        try requireNonnegative(bounds.tokens.soft, at: "\(path).tokens.soft")
        try requireNonnegative(bounds.tokens.hard, at: "\(path).tokens.hard")
    }

    private static func validate(_ counts: LiveFleetStateCountsV1, at path: String) throws {
        for (state, count) in counts.presentationCounts where count < 0 {
            throw LiveFleetContractError.schemaViolation("\(path).\(state.rawValue) must be nonnegative")
        }
    }

    private static func validate(_ counts: LiveFleetStateCountsWithTotalV1, at path: String) throws {
        try requireNonnegative(counts.total, at: "\(path).total")
        try validate(counts.counts, at: path)
    }

    private static func requireNonnegative(_ value: Double?, at path: String) throws {
        if let value, value < 0 || !value.isFinite {
            throw LiveFleetContractError.schemaViolation("\(path) must be a finite nonnegative number")
        }
    }

    private static func requireNonnegative(_ value: Double, at path: String) throws {
        try requireNonnegative(Optional(value), at: path)
    }

    private static func requireNonnegative(_ value: Int?, at path: String) throws {
        if let value { try requireNonnegative(value, at: path) }
    }

    private static func requireNonnegative(_ value: Int, at path: String) throws {
        if value < 0 {
            throw LiveFleetContractError.schemaViolation("\(path) must be nonnegative")
        }
    }

    private static func requireUnique(_ values: [String], label: String) throws {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted {
            throw LiveFleetContractError.schemaViolation("duplicate \(label): \(value)")
        }
    }
}
