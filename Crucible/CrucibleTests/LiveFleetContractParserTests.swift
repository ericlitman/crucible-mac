import Foundation
import Testing
@testable import Crucible

struct LiveFleetContractParserTests {
    @Test("All canonical CRUMAC-5 fixtures parse into their explicit delivery states")
    func canonicalFixtures() throws {
        for fixture in [LiveFleetFixture.healthy, .stale, .incomplete] {
            guard case .snapshot = try fixture.delivery else {
                Issue.record("Expected snapshot fixture: \(fixture.rawValue)")
                continue
            }
        }
        guard case let .error(incompatible) = try LiveFleetFixture.incompatible.delivery else {
            Issue.record("Expected incompatible error envelope")
            return
        }
        #expect(incompatible.contractVersion == 2)
        #expect(incompatible.error.kind == .incompatible)
        guard case let .error(failed) = try LiveFleetFixture.failed.delivery else {
            Issue.record("Expected failed error envelope")
            return
        }
        #expect(failed.error.kind == .failed)
        #expect(failed.error.retryable)
    }

    @Test("Healthy fixture preserves contract timestamps and explicit host capacity")
    @MainActor
    func healthyMapping() throws {
        guard case let .snapshot(contract) = try LiveFleetFixture.healthy.delivery else { return }
        let snapshot = contract.presentationSnapshot()

        #expect(contract.schema == "crucible.live-fleet.snapshot.v1")
        #expect(contract.contractVersion == 1)
        #expect(snapshot.sourceTimestamp == contract.sourceObservedAt)
        #expect(snapshot.hosts.map(\.id) == ["pro16"])
        #expect(snapshot.hosts[0].capacityLabel == "0/10 lanes")
        #expect(snapshot.count(for: .unknown) == 0)
    }

    @Test("Seconds and tokens remain in their contract units without inferred zeros")
    @MainActor
    func fieldUnits() throws {
        let delivery = try LiveFleetContractParser.parse(encodedFixture(snapshotWithLane()))
        guard case let .snapshot(contract) = delivery else { return }
        let lane = try #require(contract.presentationSnapshot().hosts[0].jobs[0].lanes.first)

        #expect(lane.elapsedSeconds == 90)
        #expect(lane.timeBounds == TimeBounds(softSeconds: 60, hardSeconds: 120))
        #expect(lane.tokenUse == 1_234)
        #expect(lane.tokenBounds == TokenBounds(soft: 2_000, hard: nil))
        #expect(lane.retryCount == 2)
        #expect(lane.recoverableFailures == ["transport"])

        let jobDetail = try #require(contract.presentationSnapshot().detail(for: .job(jobID: "job-1")))
        #expect(jobDetail.currentStage == nil)
        #expect(jobDetail.lanes.count == 1)
        #expect(jobDetail.lanes[0].currentStage == "Implementation")
        #expect(jobDetail.lanes[0].elapsedSeconds == 90)
        #expect(jobDetail.lanes[0].lastMeaningfulProgressAt != nil)
        #expect(jobDetail.lanes[0].tokenUse == 1_234)
        #expect(jobDetail.lanes[0].timeBounds == TimeBounds(softSeconds: 60, hardSeconds: 120))
        #expect(jobDetail.lanes[0].tokenBounds == TokenBounds(soft: 2_000, hard: nil))
    }

    @Test("Job bounds survive mapping and make bounds-only details present metrics")
    @MainActor
    func jobBoundsPresentation() throws {
        let cases: [(String, [String: Any], TimeBounds, TokenBounds)] = [
            (
                "time-only",
                [
                    "time": ["soft_seconds": 300, "hard_seconds": 600],
                    "tokens": ["soft": NSNull(), "hard": NSNull()],
                ],
                TimeBounds(softSeconds: 300, hardSeconds: 600),
                TokenBounds(soft: nil, hard: nil)
            ),
            (
                "token-only",
                [
                    "time": ["soft_seconds": NSNull(), "hard_seconds": NSNull()],
                    "tokens": ["soft": 2_000, "hard": 4_000],
                ],
                TimeBounds(softSeconds: nil, hardSeconds: nil),
                TokenBounds(soft: 2_000, hard: 4_000)
            ),
        ]

        for (label, bounds, expectedTimeBounds, expectedTokenBounds) in cases {
            var object = try snapshotWithLane()
            var jobs = object["jobs"] as! [[String: Any]]
            jobs[0]["bounds"] = bounds
            object["jobs"] = jobs

            guard case let .snapshot(contract) = try LiveFleetContractParser.parse(encodedFixture(object)) else {
                Issue.record("Expected snapshot for \(label)")
                continue
            }
            let snapshot = contract.presentationSnapshot()
            let job = try #require(snapshot.job(id: "job-1"))
            let detail = try #require(snapshot.detail(for: .job(jobID: "job-1")))

            #expect(job.timeBounds == expectedTimeBounds, "\(label) job time bounds")
            #expect(job.tokenBounds == expectedTokenBounds, "\(label) job token bounds")
            #expect(detail.timeBounds == expectedTimeBounds, "\(label) detail time bounds")
            #expect(detail.tokenBounds == expectedTokenBounds, "\(label) detail token bounds")
            #expect(detail.currentStage == nil)
            #expect(detail.elapsedSeconds == nil)
            #expect(detail.tokenUse == nil)
            #expect(detail.hasMetrics, "\(label) bounds should present the metrics grid")
        }
    }

    @Test("Retry-only and restart-only history remain independently presentable")
    @MainActor
    func independentRecoveryHistory() throws {
        let cases: [(Int?, Int?, String)] = [
            (2, nil, "2 retries"),
            (nil, 1, "1 restart"),
        ]

        for (retries, restarts, expectedLabel) in cases {
            var object = try snapshotWithLane()
            var jobs = object["jobs"] as! [[String: Any]]
            var jobAttempts = jobs[0]["attempts"] as! [String: Any]
            jobAttempts["retries"] = retries.map { $0 as Any } ?? NSNull()
            jobAttempts["restarts"] = restarts.map { $0 as Any } ?? NSNull()
            jobs[0]["attempts"] = jobAttempts

            var lanes = jobs[0]["lanes"] as! [[String: Any]]
            var laneAttempts = lanes[0]["attempts"] as! [String: Any]
            laneAttempts["retries"] = retries.map { $0 as Any } ?? NSNull()
            laneAttempts["restarts"] = restarts.map { $0 as Any } ?? NSNull()
            lanes[0]["attempts"] = laneAttempts
            jobs[0]["lanes"] = lanes
            object["jobs"] = jobs

            guard case let .snapshot(contract) = try LiveFleetContractParser.parse(encodedFixture(object)) else {
                Issue.record("Expected snapshot for \(expectedLabel)")
                continue
            }
            let snapshot = contract.presentationSnapshot()
            let jobDetail = try #require(snapshot.detail(for: .job(jobID: "job-1")))
            let lane = try #require(snapshot.job(id: "job-1")?.lanes.first)

            #expect(jobDetail.recoveryHistoryLabel == expectedLabel)
            #expect(lane.recoveryHistoryLabel == expectedLabel)
        }
    }

    @Test("Top-level counts and conditions remain authoritative in presentation")
    @MainActor
    func authoritativeFleetIntelligence() throws {
        var object = try snapshotWithLane()
        object["conditions"] = [[
            "id": "condition-stall-1",
            "type": "no_progress_stall",
            "affected": ["host_id": "pro16", "job_id": "job-1", "lane_id": "implement"],
            "first_observed_at": "2026-07-16T12:00:00.000Z",
            "last_observed_at": "2026-07-16T12:10:01.000Z",
            "severity": "warning",
            "actual": 601,
            "bound": 600,
            "action": "notify",
        ]]
        var counts = object["counts"] as! [String: Any]
        counts["conditions"] = 1
        object["counts"] = counts

        guard case let .snapshot(contract) = try LiveFleetContractParser.parse(encodedFixture(object)) else { return }
        let snapshot = contract.presentationSnapshot()

        #expect(snapshot.count(for: .active) == 1)
        #expect(snapshot.count(for: .stalled) == 0)
        #expect(snapshot.conditions.map(\.id) == ["condition-stall-1"])
        #expect(snapshot.conditions[0].type == "no_progress_stall")
        #expect(snapshot.conditions[0].jobID == "job-1")
        #expect(snapshot.conditions[0].laneID == "implement")
        #expect(snapshot.detail(for: .lane(jobID: "job-1", laneID: "implement"))?.conditions.map(\.id) == ["condition-stall-1"])
    }

    @Test("Monitor-only jobs contribute to fleet totals and remain inspectable")
    @MainActor
    func monitorOnlyJob() throws {
        var object = try snapshotWithLane()
        var queues = object["queues"] as! [[String: Any]]
        queues[0]["job_ids"] = []
        queues[0]["counts"] = ["active": 0, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
        object["queues"] = queues

        guard case let .snapshot(contract) = try LiveFleetContractParser.parse(encodedFixture(object)) else { return }
        let snapshot = contract.presentationSnapshot()

        #expect(snapshot.count(for: .active) == 1)
        #expect(snapshot.queue.isEmpty)
        #expect(snapshot.hosts[0].jobs.map(\.id) == ["job-1"])
        #expect(snapshot.job(id: "job-1") != nil)
    }

    @Test("Unassigned production jobs are selectable without a synthetic host")
    @MainActor
    func hostlessProductionJob() throws {
        var object = try snapshotWithLane()
        var jobs = object["jobs"] as! [[String: Any]]
        jobs[0]["host_id"] = NSNull()
        jobs[0]["state"] = "waiting"
        jobs[0]["lanes"] = []
        object["jobs"] = jobs
        var counts = object["counts"] as! [String: Any]
        counts["jobs"] = ["total": 1, "active": 0, "waiting": 1, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
        counts["lanes"] = ["total": 0, "active": 0, "waiting": 0, "completed": 0, "failed": 0, "blocked": 0, "stalled": 0, "unknown": 0]
        object["counts"] = counts

        guard case let .snapshot(contract) = try LiveFleetContractParser.parse(encodedFixture(object)) else { return }
        let snapshot = contract.presentationSnapshot()
        let detail = snapshot.detail(for: .job(jobID: "job-1"))

        #expect(snapshot.queue[0].hostID == nil)
        #expect(detail?.eyebrow == "Job • Unassigned queue")
        #expect(detail?.title.contains("job-1") == true)
    }

    @Test("Closed schema rejects unversioned additive fields")
    func unknownField() throws {
        var object = try fixtureObject()
        object["surprise"] = true
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(object))
        }
    }

    @Test("Duplicate JSON keys are rejected before decoding")
    func duplicateKeys() {
        let data = Data(#"{"schema":"crucible.live-fleet.error.v1","schema":"crucible.live-fleet.error.v1"}"#.utf8)
        #expect(throws: LiveFleetContractError.duplicateKey("$.schema")) {
            try LiveFleetContractParser.parse(data)
        }
    }

    @Test("Unknown closed enums and malformed timestamps are rejected")
    func enumsAndTimestamps() throws {
        var unknownEnum = try fixtureObject()
        var freshness = unknownEnum["freshness"] as! [String: Any]
        freshness["state"] = "mostly-fresh"
        unknownEnum["freshness"] = freshness
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(unknownEnum))
        }

        var badTimestamp = try fixtureObject()
        badTimestamp["generated_at"] = "yesterday"
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(badTimestamp))
        }
    }

    @Test("Duplicate identities and broken lane references are rejected")
    func references() throws {
        var duplicated = try fixtureObject(.incomplete)
        let hosts = duplicated["hosts"] as! [[String: Any]]
        duplicated["hosts"] = [hosts[0], hosts[0]]
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(duplicated))
        }

        var broken = try snapshotWithLane()
        var jobs = broken["jobs"] as! [[String: Any]]
        var lanes = jobs[0]["lanes"] as! [[String: Any]]
        lanes[0]["job_id"] = "some-other-job"
        jobs[0]["lanes"] = lanes
        broken["jobs"] = jobs
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(broken))
        }
    }

    @Test("Negative elapsed seconds are not silently normalized")
    func negativeUnits() throws {
        var object = try snapshotWithLane()
        var jobs = object["jobs"] as! [[String: Any]]
        var lanes = jobs[0]["lanes"] as! [[String: Any]]
        var progress = lanes[0]["progress"] as! [String: Any]
        progress["elapsed_seconds"] = -1
        lanes[0]["progress"] = progress
        jobs[0]["lanes"] = lanes
        object["jobs"] = jobs
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(object))
        }
    }

    @Test("Every nonnegative v1 freshness, coverage, refresh, and global count field is enforced")
    func nonnegativeContractFields() throws {
        let base = try snapshotWithLane()
        let mutations: [([String], String)] = [
            (["freshness", "age_seconds"], "freshness age"),
            (["freshness", "stale_after_seconds"], "freshness bound"),
            (["completeness", "host_coverage", "expected"], "expected hosts"),
            (["completeness", "host_coverage", "observed"], "observed hosts"),
            (["completeness", "host_coverage", "available"], "available hosts"),
            (["sources", "monitor", "refresh", "duration_ms"], "monitor refresh duration"),
            (["counts", "hosts"], "host count"),
            (["counts", "queues"], "queue count"),
            (["counts", "conditions"], "condition count"),
            (["counts", "jobs", "total"], "job total"),
            (["counts", "jobs", "active"], "job state count"),
            (["counts", "lanes", "total"], "lane total"),
            (["counts", "lanes", "stalled"], "lane state count"),
        ]

        for (path, label) in mutations {
            let object = replacingNestedValue(in: base, path: path, with: -1)
            #expect(throws: LiveFleetContractError.self, "Expected rejection for \(label)") {
                try LiveFleetContractParser.parse(encodedFixture(object))
            }
        }

        var hostMutation = base
        var hosts = hostMutation["hosts"] as! [[String: Any]]
        var hostCounts = hosts[0]["counts"] as! [String: Any]
        var byState = hostCounts["by_state"] as! [String: Any]
        byState["active"] = -1
        hostCounts["by_state"] = byState
        hosts[0]["counts"] = hostCounts
        hostMutation["hosts"] = hosts
        #expect(throws: LiveFleetContractError.self) {
            try LiveFleetContractParser.parse(encodedFixture(hostMutation))
        }
    }

    @Test("Events envelope decodes rows with absent optional detail and complete detail")
    func eventsEnvelope() throws {
        let compact: [String: Any] = [
            "schema": "crucible.live-fleet.transition.v1",
            "seq": 41,
            "recorded_at": "2026-07-19T08:01:00.000Z",
            "queue_dir": "/var/tmp/crucible/queue",
            "id": "launched:41",
            "transition_class": "launched",
            "item_id": "CRUMAC-8",
            "attempt_id": "01",
            "to_state": NSNull(),
            "action": NSNull(),
            "host": "pro16",
            "importance": "major",
        ]
        var full = compact
        full["seq"] = 42
        full["id"] = "review:42"
        full["transition_class"] = "review"
        full["to_state"] = "review_blocked"
        full["action"] = "reaped"
        full["host"] = NSNull()
        full["reason"] = "review evidence is incomplete"
        full["failure_class"] = "review_blocked"
        full["remediation"] = "rerun_review"
        full["importance"] = "important"
        let object: [String: Any] = [
            "schema": "crucible.live-fleet.events.v1",
            "contract_version": 1,
            "generated_at": "2026-07-19T08:05:00.000Z",
            "cursor": ["seq": 42],
            "events": [compact, full],
        ]

        guard case let .events(envelope) = try LiveFleetContractParser.parseEvents(encodedFixture(object)) else {
            Issue.record("Expected events envelope")
            return
        }
        #expect(envelope.schema == "crucible.live-fleet.events.v1")
        #expect(envelope.contractVersion == 1)
        #expect(envelope.cursor.seq == 42)
        #expect(envelope.events.map(\.id) == ["launched:41", "review:42"])
        #expect(envelope.events[0].reason == nil)
        #expect(envelope.events[0].host == "pro16")
        #expect(envelope.events[0].importance == .major)
        #expect(envelope.events[1].reason == "review evidence is incomplete")
        #expect(envelope.events[1].failureClass == "review_blocked")
        #expect(envelope.events[1].remediation == "rerun_review")
        #expect(envelope.events[1].importance == .important)
    }

    @Test("Every event-feed cursor error code decodes as a typed error delivery")
    func eventErrors() throws {
        for code in ["cursor_expired", "source_invalid", "invalid_cursor"] {
            let object: [String: Any] = [
                "schema": "crucible.live-fleet.error.v1",
                "contract_version": 1,
                "generated_at": "2026-07-19T08:05:00.000Z",
                "error": [
                    "code": code,
                    "kind": "failed",
                    "message": "event feed error",
                    "retryable": code != "invalid_cursor",
                    "source": "transitions-ledger",
                ],
            ]
            guard case let .error(envelope) = try LiveFleetContractParser.parseEvents(encodedFixture(object)) else {
                Issue.record("Expected error envelope for \(code)")
                continue
            }
            #expect(envelope.error.code == code)
            #expect(envelope.error.kind == .failed)
        }
    }
}

private func replacingNestedValue(
    in object: [String: Any],
    path: [String],
    with value: Any
) -> [String: Any] {
    var result = object
    guard let key = path.first else { return result }
    if path.count == 1 {
        result[key] = value
    } else if let child = result[key] as? [String: Any] {
        result[key] = replacingNestedValue(in: child, path: Array(path.dropFirst()), with: value)
    }
    return result
}
