#if DEBUG
import Foundation

enum PreviewFixtures {
    static let sourceTimestamp = Date(timeIntervalSince1970: 1_783_891_800)

    static let fleet = FleetSnapshot(
        contractVersion: "crucible.fleet/v1-preview",
        sourceTimestamp: sourceTimestamp,
        queue: [
            QueueItemSnapshot(id: "CRU-142", title: "Parallel build lanes", hostID: "forge-01", state: .active),
            QueueItemSnapshot(id: "CRU-143", title: "Awaiting capacity", hostID: nil, state: .waiting),
            QueueItemSnapshot(id: "CRU-138", title: "Telemetry cleanup", hostID: "forge-02", state: .completed),
            QueueItemSnapshot(id: "CRU-139", title: "Schema migration", hostID: "forge-03", state: .failed),
            QueueItemSnapshot(id: "CRU-140", title: "Dependency audit", hostID: "forge-03", state: .blocked),
            QueueItemSnapshot(id: "CRU-141", title: "Release investigation", hostID: "forge-04", state: .stalled),
        ],
        hosts: [
            HostSnapshot(
                id: "forge-01",
                displayName: "forge-01",
                condition: .busy,
                activeLaneCount: 7,
                laneCapacity: 10,
                jobs: [
                    JobSnapshot(
                        id: "CRU-142",
                        hostID: "forge-01",
                        title: "Parallel build lanes",
                        state: .active,
                        currentStage: "Implement",
                        elapsedSeconds: 1_428,
                        lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-92),
                        retryCount: 1,
                        restartCount: 0,
                        recoverableFailures: ["SwiftPM cache miss recovered"],
                        tokenUse: 48_320,
                        tokenBounds: TokenBounds(soft: nil, hard: nil),
                        timeBounds: TimeBounds(softSeconds: nil, hardSeconds: nil),
                        lanes: [
                            LaneSnapshot(
                                id: "implement",
                                name: "Implementation",
                                state: .active,
                                currentStage: "Implement",
                                elapsedSeconds: 742,
                                lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-92),
                                retryCount: 1,
                                restartCount: 0,
                                recoverableFailures: ["SwiftPM cache miss recovered"],
                                tokenUse: 31_880,
                                tokenBounds: TokenBounds(soft: 100_000, hard: 150_000),
                                timeBounds: TimeBounds(softSeconds: nil, hardSeconds: 1_800)
                            ),
                            LaneSnapshot(
                                id: "review",
                                name: "Review",
                                state: .waiting,
                                currentStage: "Queued",
                                elapsedSeconds: 0,
                                lastMeaningfulProgressAt: nil,
                                retryCount: 0,
                                restartCount: 0,
                                recoverableFailures: [],
                                tokenUse: 0,
                                tokenBounds: TokenBounds(soft: 50_000, hard: 80_000),
                                timeBounds: TimeBounds(softSeconds: nil, hardSeconds: 1_200)
                            ),
                        ]
                    ),
                ]
            ),
            HostSnapshot(
                id: "forge-02",
                displayName: "forge-02",
                condition: .available,
                activeLaneCount: 0,
                laneCapacity: 10,
                jobs: []
            ),
            HostSnapshot(
                id: "forge-03",
                displayName: "forge-03",
                condition: .degraded,
                activeLaneCount: 1,
                laneCapacity: 10,
                jobs: [
                    JobSnapshot(
                        id: "CRU-140",
                        hostID: "forge-03",
                        title: "Dependency audit",
                        state: .blocked,
                        currentStage: "Investigate",
                        elapsedSeconds: 2_940,
                        lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-510),
                        retryCount: 2,
                        restartCount: 1,
                        recoverableFailures: ["Registry timeout recovered", "Lock contention recovered"],
                        tokenUse: 92_110,
                        tokenBounds: TokenBounds(soft: nil, hard: nil),
                        timeBounds: TimeBounds(softSeconds: nil, hardSeconds: nil),
                        lanes: [
                            LaneSnapshot(
                                id: "investigate",
                                name: "Investigation",
                                state: .blocked,
                                currentStage: "Investigate",
                                elapsedSeconds: 2_940,
                                lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-510),
                                retryCount: 2,
                                restartCount: 1,
                                recoverableFailures: ["Registry timeout recovered", "Lock contention recovered"],
                                tokenUse: 92_110,
                                tokenBounds: TokenBounds(soft: 100_000, hard: 150_000),
                                timeBounds: TimeBounds(softSeconds: nil, hardSeconds: 3_600)
                            ),
                        ]
                    ),
                ]
            ),
            HostSnapshot(
                id: "forge-04",
                displayName: "forge-04",
                condition: .degraded,
                activeLaneCount: 1,
                laneCapacity: 10,
                jobs: [
                    JobSnapshot(
                        id: "CRU-141",
                        hostID: "forge-04",
                        title: "Release investigation",
                        state: .stalled,
                        currentStage: "Test",
                        elapsedSeconds: 4_260,
                        lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-780),
                        retryCount: 3,
                        restartCount: 2,
                        recoverableFailures: ["Agent resumed after transport failure"],
                        tokenUse: 144_810,
                        tokenBounds: TokenBounds(soft: nil, hard: nil),
                        timeBounds: TimeBounds(softSeconds: nil, hardSeconds: nil),
                        lanes: [
                            LaneSnapshot(
                                id: "test",
                                name: "Test & Verify",
                                state: .stalled,
                                currentStage: "Test",
                                elapsedSeconds: 4_260,
                                lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-780),
                                retryCount: 3,
                                restartCount: 2,
                                recoverableFailures: ["Agent resumed after transport failure"],
                                tokenUse: 144_810,
                                tokenBounds: TokenBounds(soft: 120_000, hard: 180_000),
                                timeBounds: TimeBounds(softSeconds: nil, hardSeconds: 3_600)
                            ),
                        ]
                    ),
                ]
            ),
        ],
        jobs: [
            JobSnapshot(
                id: "CRU-143",
                hostID: nil,
                title: "Awaiting capacity",
                state: .waiting,
                currentStage: nil,
                elapsedSeconds: nil,
                lastMeaningfulProgressAt: nil,
                retryCount: 0,
                restartCount: 0,
                recoverableFailures: [],
                tokenUse: nil,
                tokenBounds: TokenBounds(soft: nil, hard: nil),
                timeBounds: TimeBounds(softSeconds: nil, hardSeconds: nil),
                lanes: []
            ),
        ]
    )

    static let healthyPresentation = FleetPresentation(
        snapshot: fleet,
        freshness: .preview(asOf: sourceTimestamp),
        lastSuccessfulRefresh: sourceTimestamp,
        errorMessage: nil,
        isPreviewData: true
    )

    static let stalePresentation = FleetPresentation(
        snapshot: fleet,
        freshness: .stale(asOf: sourceTimestamp),
        lastSuccessfulRefresh: sourceTimestamp,
        errorMessage: "Previewing a stale CLI response; last refresh did not complete.",
        isPreviewData: true
    )

    static let failedPresentation = FleetPresentation(
        snapshot: fleet,
        freshness: .stale(asOf: sourceTimestamp),
        lastSuccessfulRefresh: sourceTimestamp,
        errorMessage: "Previewing a CLI launch failure while preserving the last known snapshot.",
        isPreviewData: true
    )

    static let incompatiblePresentation = FleetPresentation(
        snapshot: fleet,
        freshness: .incompatible,
        lastSuccessfulRefresh: sourceTimestamp,
        errorMessage: "unsupported live-fleet contract version: 2",
        isPreviewData: true
    )
}
#endif
