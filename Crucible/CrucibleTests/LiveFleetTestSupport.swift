import Foundation
@testable import Crucible

enum LiveFleetFixture: String {
    case healthy = "live-fleet-healthy-v1.json"
    case stale = "live-fleet-stale-v1.json"
    case incomplete = "live-fleet-incomplete-v1.json"
    case incompatible = "live-fleet-incompatible-v1.json"
    case failed = "live-fleet-failed-v1.json"

    var data: Data {
        get throws {
            let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            return try Data(contentsOf: testsDirectory.appending(path: "Fixtures").appending(path: rawValue))
        }
    }

    var delivery: LiveFleetDelivery {
        get throws { try LiveFleetContractParser.parse(data) }
    }
}

func fixtureObject(_ fixture: LiveFleetFixture = .healthy) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: fixture.data) as! [String: Any]
}

func encodedFixture(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

func snapshotWithLane() throws -> [String: Any] {
    var root = try fixtureObject()
    let lane: [String: Any] = [
        "id": "implement", "job_id": "job-1", "run_id": "run-1", "item_id": "CRU-1",
        "stage": ["id": "implement", "role": "Implementation", "phase": "running"],
        "model": "openai/codex", "host_id": "pro16", "state": "active", "raw_state": "running",
        "progress": [
            "state": "running", "message": "Editing", "started_at": "2026-07-16T11:58:35.000Z",
            "last_observed_at": "2026-07-16T12:00:05.000Z", "last_meaningful_at": "2026-07-16T12:00:00.000Z",
            "semantic_source": "scheduler_progress_transition", "elapsed_seconds": 90, "no_progress_bound_seconds": 600,
        ],
        "attempts": ["current": "attempt-1", "total": 1, "retries": 2, "restarts": 1, "retry_limit": 3, "history": [], "recoveries": []],
        "failures": [[
            "id": "failure-1", "type": "transport", "occurred_at": "2026-07-16T11:59:00.000Z",
            "recoverable": true, "recovery_action": "resume", "evidence_available": true,
        ]],
        "usage": [
            "available": true, "source": "attempt_live", "observed_at": "2026-07-16T12:00:04.000Z",
            "measurement_quality": "measured",
            "tokens": ["input": 1000, "output": 200, "cache_read": 34, "cache_write": 0, "reasoning_output": 0, "total": 1234],
        ],
        "bounds": ["time": ["soft_seconds": 60, "hard_seconds": 120], "tokens": ["soft": 2000, "hard": NSNull()]],
    ]
    let job: [String: Any] = [
        "id": "job-1", "queue_id": "/state/queue", "run_id": "run-1", "title": "Build fleet view",
        "issue_ids": ["CRU-1"], "host_id": "pro16", "state": "active", "raw_state": "running",
        "lifecycle": ["terminal": false],
        "timestamps": ["created_at": "2026-07-16T11:58:35.000Z", "updated_at": "2026-07-16T12:00:05.000Z", "last_transition_at": "2026-07-16T12:00:00.000Z"],
        "attempts": ["current": "attempt-1", "total": 1, "retries": 2, "restarts": 1, "retry_limit": 3, "history": [], "recoveries": []],
        "failures": [], "bounds": ["time": ["soft_seconds": NSNull(), "hard_seconds": NSNull()], "tokens": ["soft": NSNull(), "hard": NSNull()]],
        "lanes": [lane],
        "provenance": ["source": "supervisor_queue", "source_id": "job-1", "run_dir": "/state/run-1", "detail_reasons": []],
    ]
    root["jobs"] = [job]
    var queues = root["queues"] as! [[String: Any]]
    queues[0]["job_ids"] = ["job-1"]
    queues[0]["counts"] = ["active": 1, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
    root["queues"] = queues
    var hosts = root["hosts"] as! [[String: Any]]
    var hostCounts = hosts[0]["counts"] as! [String: Any]
    hostCounts["active"] = 1
    hostCounts["total"] = 1
    hostCounts["by_state"] = ["active": 1, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
    hosts[0]["counts"] = hostCounts
    root["hosts"] = hosts
    var counts = root["counts"] as! [String: Any]
    counts["jobs"] = ["total": 1, "active": 1, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
    counts["lanes"] = ["total": 1, "active": 1, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
    root["counts"] = counts
    return root
}

actor StubCLIClient: CrucibleCLIClient {
    enum StubError: Error { case failed }

    private let delivery: LiveFleetDelivery
    private let delay: Duration
    private let shouldFail: Bool
    private(set) var calls = 0

    init(delivery: LiveFleetDelivery, delay: Duration = .zero, shouldFail: Bool = false) {
        self.delivery = delivery
        self.delay = delay
        self.shouldFail = shouldFail
    }

    func liveFleetSnapshot() async throws -> LiveFleetDelivery {
        calls += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        if shouldFail { throw StubError.failed }
        return delivery
    }

    func callCount() -> Int { calls }
}
