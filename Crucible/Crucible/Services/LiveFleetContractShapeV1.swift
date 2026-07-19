import Foundation

nonisolated enum LiveFleetContractShapeV1 {
    static func validateSnapshot(_ root: [String: Any]) throws {
        try object(root, at: "$", keys: [
            "schema", "contract_version", "generated_at", "source_observed_at", "controller_generation",
            "freshness", "completeness", "sources", "counts", "hosts", "queues", "jobs", "conditions",
        ])
        try child(root, "freshness", keys: ["state", "age_seconds", "stale_after_seconds"])
        let completeness = try child(root, "completeness", keys: ["state", "reasons", "host_coverage", "jobs_truncated"])
        try child(completeness, "host_coverage", keys: ["expected", "observed", "available"])
        try validateSources(try dictionary(root["sources"], at: "$.sources"))
        try validateSnapshotCounts(try dictionary(root["counts"], at: "$.counts"))
        try array(root["hosts"], at: "$.hosts").enumerated().forEach { index, value in
            try validateHost(try dictionary(value, at: "$.hosts[\(index)]"), at: "$.hosts[\(index)]")
        }
        try array(root["queues"], at: "$.queues").enumerated().forEach { index, value in
            try validateQueue(try dictionary(value, at: "$.queues[\(index)]"), at: "$.queues[\(index)]")
        }
        try array(root["jobs"], at: "$.jobs").enumerated().forEach { index, value in
            try validateJob(try dictionary(value, at: "$.jobs[\(index)]"), at: "$.jobs[\(index)]")
        }
        try array(root["conditions"], at: "$.conditions").enumerated().forEach { index, value in
            let path = "$.conditions[\(index)]"
            let row = try dictionary(value, at: path)
            try object(row, at: path, keys: ["id", "type", "affected", "first_observed_at", "last_observed_at", "severity", "actual", "bound", "action"])
            try child(row, "affected", at: path, keys: ["host_id", "job_id", "lane_id"])
            try enumValue(row["severity"], at: "\(path).severity", allowed: ["info", "warning", "error", "critical"])
        }
        try enumValue(root["freshness"], key: "state", at: "$.freshness", allowed: ["fresh", "stale"])
        try enumValue(root["completeness"], key: "state", at: "$.completeness", allowed: ["complete", "partial"])
    }

    static func validateError(_ root: [String: Any]) throws {
        try object(root, at: "$", keys: ["schema", "contract_version", "generated_at", "error"])
        let error = try child(root, "error", keys: ["code", "kind", "message", "retryable", "source"])
        try enumValue(error["kind"], at: "$.error.kind", allowed: ["unavailable", "incompatible", "failed"])
    }

    static func validateEvents(_ root: [String: Any]) throws {
        try object(root, at: "$", keys: ["schema", "contract_version", "generated_at", "cursor", "events"])
        try child(root, "cursor", keys: ["seq"])
        try array(root["events"], at: "$.events").enumerated().forEach { index, value in
            let path = "$.events[\(index)]"
            let row = try dictionary(value, at: path)
            try relaxedObject(
                row,
                at: path,
                requiredKeys: [
                    "schema", "seq", "recorded_at", "id", "transition_class", "item_id",
                    "importance",
                ],
                optionalKeys: [
                    "queue_dir", "attempt_id", "to_state", "action", "host", "reason",
                    "failure_class", "remediation",
                ]
            )
            guard row["schema"] as? String == "crucible.live-fleet.transition.v1" else {
                throw LiveFleetContractError.schemaViolation("\(path).schema has an unsupported value")
            }
            try enumValue(row["importance"], at: "\(path).importance", allowed: ["major", "important"])
            for key in ["reason", "failure_class", "remediation"] where row.keys.contains(key) {
                guard row[key] is String else {
                    throw LiveFleetContractError.schemaViolation("\(path).\(key) must be a string when present")
                }
            }
        }
    }

    private static func validateSources(_ sources: [String: Any]) throws {
        try object(sources, at: "$.sources", keys: ["queue", "monitor", "capacity"])
        try child(sources, "queue", at: "$.sources", keys: ["path", "observed_at", "schema"])
        let monitor = try child(sources, "monitor", at: "$.sources", keys: ["path", "observed_at", "schema", "refresh"])
        let refresh = try child(monitor, "refresh", at: "$.sources.monitor", keys: ["mode", "attempted", "status", "duration_ms", "coalesced", "error"])
        try enumValue(refresh["mode"], at: "$.sources.monitor.refresh.mode", allowed: ["fresh", "cached"])
        try enumValue(refresh["status"], at: "$.sources.monitor.refresh.status", allowed: ["cached", "fresh_cache", "fresh", "partial", "failed"])
        try child(sources, "capacity", at: "$.sources", keys: ["path", "observed_at", "schema"])
    }

    private static func validateSnapshotCounts(_ counts: [String: Any]) throws {
        try object(counts, at: "$.counts", keys: ["hosts", "queues", "jobs", "lanes", "conditions"])
        try child(counts, "jobs", at: "$.counts", keys: stateCountKeys + ["total"])
        try child(counts, "lanes", at: "$.counts", keys: stateCountKeys + ["total"])
    }

    private static func validateHost(_ host: [String: Any], at path: String) throws {
        try object(host, at: path, keys: ["id", "address", "transport", "state", "observed_at", "capacity", "counts", "jobs_truncated", "resources", "pressure", "alerts", "error"])
        try enumValue(host["state"], at: "\(path).state", allowed: ["available", "unavailable"])
        try child(host, "capacity", at: path, keys: ["configured_lane_limit", "reported_limit", "active", "queue_depth"])
        let counts = try child(host, "counts", at: path, keys: ["active", "terminal", "total", "by_state"])
        try child(counts, "by_state", at: "\(path).counts", keys: stateCountKeys)
        if !(host["resources"] is NSNull) {
            try child(host, "resources", at: path, keys: ["available", "mem_headroom_percent", "swap_used_percent", "swap_used_gigabytes", "load_one_normalized", "runner_fraction", "disk_free_percent", "error"])
        }
        if !(host["pressure"] is NSNull) {
            try child(host, "pressure", at: path, keys: ["state", "reason", "sampled_at"])
        }
        try array(host["alerts"], at: "\(path).alerts").enumerated().forEach { index, alert in
            try object(try dictionary(alert, at: "\(path).alerts[\(index)]"), at: "\(path).alerts[\(index)]", keys: ["type", "severity", "message"])
        }
    }

    private static func validateQueue(_ queue: [String: Any], at path: String) throws {
        try object(queue, at: path, keys: ["id", "observed_at", "heartbeat", "counts", "job_ids"])
        if !(queue["heartbeat"] is NSNull) {
            try child(queue, "heartbeat", at: path, keys: ["state", "at", "next_tick_at"])
        }
        try child(queue, "counts", at: path, keys: stateCountKeys)
    }

    private static func validateJob(_ job: [String: Any], at path: String) throws {
        try object(job, at: path, keys: ["id", "queue_id", "run_id", "title", "issue_ids", "host_id", "state", "raw_state", "lifecycle", "timestamps", "attempts", "failures", "bounds", "lanes", "provenance"])
        try enumValue(job["state"], at: "\(path).state", allowed: stateValues)
        try child(job, "lifecycle", at: path, keys: ["terminal"])
        try child(job, "timestamps", at: path, keys: ["created_at", "updated_at", "last_transition_at"])
        try validateAttempts(try dictionary(job["attempts"], at: "\(path).attempts"), at: "\(path).attempts")
        try validateFailures(job["failures"], at: "\(path).failures")
        try validateBounds(try dictionary(job["bounds"], at: "\(path).bounds"), at: "\(path).bounds")
        try array(job["lanes"], at: "\(path).lanes").enumerated().forEach { index, lane in
            try validateLane(try dictionary(lane, at: "\(path).lanes[\(index)]"), at: "\(path).lanes[\(index)]")
        }
        try child(job, "provenance", at: path, keys: ["source", "source_id", "run_dir", "detail_reasons"])
    }

    private static func validateLane(_ lane: [String: Any], at path: String) throws {
        try object(lane, at: path, keys: ["id", "job_id", "run_id", "item_id", "stage", "model", "host_id", "state", "raw_state", "progress", "attempts", "failures", "usage", "bounds"])
        try enumValue(lane["state"], at: "\(path).state", allowed: stateValues)
        try child(lane, "stage", at: path, keys: ["id", "role", "phase"])
        let progress = try child(lane, "progress", at: path, keys: ["state", "message", "started_at", "last_observed_at", "last_meaningful_at", "semantic_source", "elapsed_seconds", "no_progress_bound_seconds"])
        try enumValue(progress["semantic_source"], at: "\(path).progress.semantic_source", allowed: ["scheduler_progress_transition", "best_available_transition", "host_monitor_transition", "unavailable"])
        try validateAttempts(try dictionary(lane["attempts"], at: "\(path).attempts"), at: "\(path).attempts")
        try validateFailures(lane["failures"], at: "\(path).failures")
        let usage = try child(lane, "usage", at: path, keys: ["available", "source", "observed_at", "measurement_quality", "tokens"])
        if !(usage["tokens"] is NSNull) {
            try child(usage, "tokens", at: "\(path).usage", keys: ["input", "output", "cache_read", "cache_write", "reasoning_output", "total"])
        }
        try validateBounds(try dictionary(lane["bounds"], at: "\(path).bounds"), at: "\(path).bounds")
    }

    private static func validateAttempts(_ attempts: [String: Any], at path: String) throws {
        try object(attempts, at: path, keys: ["current", "total", "retries", "restarts", "retry_limit", "history", "recoveries"])
        try array(attempts["history"], at: "\(path).history").enumerated().forEach { index, row in
            try object(try dictionary(row, at: "\(path).history[\(index)]"), at: "\(path).history[\(index)]", keys: ["attempt_id", "state", "ended_at", "failure_type"])
        }
        try array(attempts["recoveries"], at: "\(path).recoveries").enumerated().forEach { index, row in
            try object(try dictionary(row, at: "\(path).recoveries[\(index)]"), at: "\(path).recoveries[\(index)]", keys: ["at", "continuation", "reason"])
        }
    }

    private static func validateFailures(_ value: Any?, at path: String) throws {
        try array(value, at: path).enumerated().forEach { index, row in
            try object(try dictionary(row, at: "\(path)[\(index)]"), at: "\(path)[\(index)]", keys: ["id", "type", "occurred_at", "recoverable", "recovery_action", "evidence_available"])
        }
    }

    private static func validateBounds(_ bounds: [String: Any], at path: String) throws {
        try object(bounds, at: path, keys: ["time", "tokens"])
        try child(bounds, "time", at: path, keys: ["soft_seconds", "hard_seconds"])
        try child(bounds, "tokens", at: path, keys: ["soft", "hard"])
    }

    private static let stateCountKeys = ["active", "waiting", "completed", "failed", "blocked", "stalled", "unknown"]
    private static let stateValues = stateCountKeys

    @discardableResult
    private static func child(_ parent: [String: Any], _ key: String, at path: String = "$", keys: [String]) throws -> [String: Any] {
        let value = try dictionary(parent[key], at: "\(path).\(key)")
        try object(value, at: "\(path).\(key)", keys: keys)
        return value
    }

    private static func object(_ value: [String: Any], at path: String, keys: [String]) throws {
        let actual = Set(value.keys)
        let expected = Set(keys)
        guard actual == expected else {
            let missing = expected.subtracting(actual).sorted()
            let extra = actual.subtracting(expected).sorted()
            throw LiveFleetContractError.schemaViolation("\(path) keys differ; missing=\(missing) extra=\(extra)")
        }
    }

    private static func relaxedObject(
        _ value: [String: Any],
        at path: String,
        requiredKeys: [String],
        optionalKeys: [String]
    ) throws {
        let actual = Set(value.keys)
        let required = Set(requiredKeys)
        let allowed = required.union(optionalKeys)
        let missing = required.subtracting(actual).sorted()
        let extra = actual.subtracting(allowed).sorted()
        guard missing.isEmpty, extra.isEmpty else {
            throw LiveFleetContractError.schemaViolation("\(path) keys differ; missing=\(missing) extra=\(extra)")
        }
    }

    private static func dictionary(_ value: Any?, at path: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw LiveFleetContractError.schemaViolation("\(path) must be an object")
        }
        return value
    }

    private static func array(_ value: Any?, at path: String) throws -> [Any] {
        guard let value = value as? [Any] else {
            throw LiveFleetContractError.schemaViolation("\(path) must be an array")
        }
        return value
    }

    private static func enumValue(_ parent: Any?, key: String, at path: String, allowed: [String]) throws {
        let object = try dictionary(parent, at: path)
        try enumValue(object[key], at: "\(path).\(key)", allowed: allowed)
    }

    private static func enumValue(_ value: Any?, at path: String, allowed: [String]) throws {
        guard let value = value as? String, allowed.contains(value) else {
            throw LiveFleetContractError.schemaViolation("\(path) has an unsupported value")
        }
    }
}
