import Foundation
import Testing
@testable import Crucible

@MainActor
struct FleetNotificationTests {
    @Test("Important condition planner covers every required CLI condition with actionable identity and copy")
    func requiredConditionCopy() throws {
        let conditions = [
            condition(id: "stall", type: "no_progress_stall", actual: 720, bound: 600),
            condition(id: "time-soft", type: "time_soft_bound_exceeded", actual: 1_500, bound: 1_260),
            condition(id: "time-hard", type: "time_hard_bound_exceeded", actual: 3_603, bound: 3_600),
            condition(id: "token-soft", type: "token_soft_bound_exceeded", actual: 205_000, bound: 200_000),
            condition(id: "token-hard", type: "token_hard_bound_exceeded", actual: 260_000, bound: 250_000),
            condition(id: "source-stale", type: "source_stale", actual: 700, bound: 600),
        ]

        let alerts = ImportantConditionAlertPlanner.alerts(for: snapshot(conditions: conditions))

        #expect(alerts.map(\.episodeID) == ["stall", "time-soft", "time-hard", "token-soft", "token-hard"])
        #expect(alerts.map(\.title) == [
            "Lane stalled",
            "Soft time limit exceeded",
            "Hard time limit exceeded",
            "Soft token limit exceeded",
            "Hard token limit exceeded",
        ])
        #expect(alerts.allSatisfy { $0.subtitle == "pro16 · MOB-1325 · implementer" })
        #expect(alerts[0].body == "No meaningful progress for 12m; stall threshold is 10m. Open Crucible to inspect this lane.")
        #expect(alerts[2].body == "Running for 1h 0m; hard limit is 1h 0m. Open Crucible to inspect this lane.")
        #expect(alerts[3].body == "Used 205.0K tokens; soft limit is 200.0K. Open Crucible to inspect this lane.")
    }

    @Test("Planner refuses conditions that cannot identify host, job, and lane")
    func incompleteIdentityIsNotActionable() {
        let incomplete = FleetConditionSnapshot(
            id: "missing-lane",
            type: "no_progress_stall",
            severity: .warning,
            hostID: "pro16",
            jobID: "MOB-1325",
            laneID: nil,
            firstObservedAt: .now,
            lastObservedAt: .now,
            actual: 720,
            bound: 600,
            action: "inspect_lane"
        )

        #expect(ImportantConditionAlertPlanner.alerts(for: snapshot(conditions: [incomplete])).isEmpty)
    }

    @Test("Reading status never requests permission; the contextual action does")
    func permissionIsExplicit() async {
        let client = FakeSystemNotificationClient(authorizationState: .notDetermined)
        let coordinator = FleetNotificationCoordinator(
            client: client,
            episodeStore: MemoryNotificationEpisodeStore()
        )
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: coordinator
        )

        await state.refreshNotificationAuthorizationState()
        #expect(state.notificationAuthorizationState == .notDetermined)
        #expect(client.requestCount == 0)

        await state.requestNotificationAuthorization()
        #expect(state.notificationAuthorizationState == .authorized)
        #expect(client.requestCount == 1)
    }

    @Test("A condition present on the first accepted refresh is delivered")
    func firstRefreshDelivers() async throws {
        let harness = notificationHarness(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "first")]))
        await state.waitForNotificationEvaluation()

        #expect(harness.client.deliveredAlerts.map(\.episodeID) == ["first"])
        #expect(harness.store.contains("first"))
    }

    @Test("A still-active condition delivers once after explicit authorization")
    func pendingConditionDeliversAfterAuthorization() async throws {
        let harness = notificationHarness(authorizationState: .notDetermined)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "pending")]))
        await state.waitForNotificationEvaluation()
        #expect(harness.client.deliveredAlerts.isEmpty)
        #expect(!harness.store.contains("pending"))

        await state.requestNotificationAuthorization()
        #expect(harness.client.deliveredAlerts.map(\.episodeID) == ["pending"])
        #expect(harness.store.contains("pending"))

        state.apply(try delivery(.healthy, conditions: [condition(id: "pending")]))
        await state.waitForNotificationEvaluation()
        #expect(harness.client.deliveredAlerts.map(\.episodeID) == ["pending"])
    }

    @Test("A fresh partial snapshot is accepted for notifications")
    func freshPartialDelivers() async throws {
        let harness = notificationHarness(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )

        state.apply(try delivery(.incomplete, conditions: [condition(id: "partial")]))
        await state.waitForNotificationEvaluation()

        #expect(harness.client.deliveredAlerts.map(\.episodeID) == ["partial"])
        #expect(state.presentation.errorMessage?.contains("incomplete") == true)
    }

    @Test("Stale, error, and out-of-order deliveries never reach the planner")
    func rejectedDeliveriesDoNotAlert() async throws {
        let harness = notificationHarness(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )

        state.apply(try delivery(.stale, conditions: [condition(id: "stale")]))
        state.apply(try LiveFleetFixture.failed.delivery)

        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T12:02:05.000Z",
            sourceObservedAt: "2026-07-16T12:02:00.000Z"
        ))
        state.apply(try delivery(
            .healthy,
            conditions: [condition(id: "older")],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))
        await state.waitForNotificationEvaluation()

        #expect(harness.client.deliveredAlerts.isEmpty)
    }

    @Test("Denial and scheduling failures do not consume an episode")
    func denialAndFailureRetry() async {
        let deniedHarness = notificationHarness(authorizationState: .denied)
        let active = snapshot(conditions: [condition(id: "denied")])

        let deniedResult = await deniedHarness.coordinator.process(active)
        #expect(deniedResult.authorizationState == .denied)
        #expect(!deniedHarness.store.contains("denied"))

        deniedHarness.client.setAuthorizationState(.authorized)
        let authorizedResult = await deniedHarness.coordinator.process(active)
        #expect(authorizedResult.deliveredEpisodeIDs == ["denied"])
        #expect(deniedHarness.store.contains("denied"))

        let failingHarness = notificationHarness(
            authorizationState: .authorized,
            deliveryFailuresRemaining: 1
        )
        let retrySnapshot = snapshot(conditions: [condition(id: "retry")])
        let failedResult = await failingHarness.coordinator.process(retrySnapshot)
        #expect(failedResult.deliveryErrors.count == 1)
        #expect(!failingHarness.store.contains("retry"))

        let retriedResult = await failingHarness.coordinator.process(retrySnapshot)
        #expect(retriedResult.deliveredEpisodeIDs == ["retry"])
        #expect(failingHarness.client.deliveryAttemptCount == 2)
        #expect(failingHarness.store.contains("retry"))
    }

    @Test("Delivered condition episodes deduplicate across refreshes")
    func unchangedEpisodeDeduplicates() async {
        let harness = notificationHarness(authorizationState: .authorized)
        let active = snapshot(conditions: [condition(id: "same-episode")])

        _ = await harness.coordinator.process(active)
        _ = await harness.coordinator.process(active)

        #expect(harness.client.deliveredAlerts.map(\.episodeID) == ["same-episode"])
    }

    @Test("UserDefaults delivery history persists and remains bounded")
    func persistenceIsBounded() async {
        let suiteName = "CrucibleTests.Notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "episodes"

        let firstStore = UserDefaultsNotificationEpisodeStore(defaults: defaults, key: key, limit: 2)
        firstStore.record("one")
        firstStore.record("two")
        firstStore.record("three")

        let relaunchedStore = UserDefaultsNotificationEpisodeStore(defaults: defaults, key: key, limit: 2)
        #expect(!relaunchedStore.contains("one"))
        #expect(relaunchedStore.contains("two"))
        #expect(relaunchedStore.contains("three"))
    }

    private func notificationHarness(
        authorizationState: NotificationAuthorizationState,
        deliveryFailuresRemaining: Int = 0
    ) -> NotificationHarness {
        let client = FakeSystemNotificationClient(
            authorizationState: authorizationState,
            deliveryFailuresRemaining: deliveryFailuresRemaining
        )
        let store = MemoryNotificationEpisodeStore()
        return NotificationHarness(
            client: client,
            store: store,
            coordinator: FleetNotificationCoordinator(client: client, episodeStore: store)
        )
    }

    private func snapshot(
        conditions: [FleetConditionSnapshot],
        sourceTimestamp: Date = Date(timeIntervalSince1970: 1_752_665_200)
    ) -> FleetSnapshot {
        FleetSnapshot(
            contractVersion: "1",
            sourceTimestamp: sourceTimestamp,
            queue: [],
            hosts: [],
            conditions: conditions
        )
    }

    private func condition(
        id: String,
        type: String = "no_progress_stall",
        actual: Double = 720,
        bound: Double = 600
    ) -> FleetConditionSnapshot {
        FleetConditionSnapshot(
            id: id,
            type: type,
            severity: .warning,
            hostID: "pro16",
            jobID: "MOB-1325",
            laneID: "implementer",
            firstObservedAt: Date(timeIntervalSince1970: 1_752_664_480),
            lastObservedAt: Date(timeIntervalSince1970: 1_752_665_200),
            actual: actual,
            bound: bound,
            action: "inspect_lane"
        )
    }

    private func delivery(
        _ fixture: LiveFleetFixture,
        conditions: [FleetConditionSnapshot],
        generatedAt: String? = nil,
        sourceObservedAt: String? = nil
    ) throws -> LiveFleetDelivery {
        var object = try fixtureObject(fixture)
        if let generatedAt { object["generated_at"] = generatedAt }
        if let sourceObservedAt { object["source_observed_at"] = sourceObservedAt }
        if !conditions.isEmpty {
            object["jobs"] = try snapshotWithLane()["jobs"]
        }
        object["conditions"] = conditions.map { condition in
            [
                "id": condition.id,
                "type": condition.type,
                "affected": [
                    "host_id": condition.hostID as Any,
                    "job_id": "job-1",
                    "lane_id": "implement",
                ],
                "first_observed_at": "2026-07-16T12:00:00.000Z",
                "last_observed_at": "2026-07-16T12:12:00.000Z",
                "severity": condition.severity.rawValue,
                "actual": condition.actual as Any,
                "bound": condition.bound as Any,
                "action": condition.action as Any,
            ]
        }
        var counts = object["counts"] as! [String: Any]
        counts["conditions"] = conditions.count
        object["counts"] = counts
        return try LiveFleetContractParser.parse(encodedFixture(object))
    }
}

@MainActor
private struct NotificationHarness {
    let client: FakeSystemNotificationClient
    let store: MemoryNotificationEpisodeStore
    let coordinator: FleetNotificationCoordinator
}

nonisolated private final class FakeSystemNotificationClient: SystemNotificationClient, @unchecked Sendable {
    enum FakeError: Error { case deliveryFailed }

    private let lock = NSLock()
    private var currentAuthorizationState: NotificationAuthorizationState
    private var deliveryFailuresRemaining: Int
    private var storedRequestCount = 0
    private var storedDeliveryAttemptCount = 0
    private var storedDeliveredAlerts: [FleetAlert] = []

    var requestCount: Int { lock.withLock { storedRequestCount } }
    var deliveryAttemptCount: Int { lock.withLock { storedDeliveryAttemptCount } }
    var deliveredAlerts: [FleetAlert] { lock.withLock { storedDeliveredAlerts } }

    init(
        authorizationState: NotificationAuthorizationState,
        deliveryFailuresRemaining: Int = 0
    ) {
        currentAuthorizationState = authorizationState
        self.deliveryFailuresRemaining = deliveryFailuresRemaining
    }

    func authorizationState() async -> NotificationAuthorizationState {
        lock.withLock { currentAuthorizationState }
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        lock.withLock {
            storedRequestCount += 1
            if currentAuthorizationState == .notDetermined {
                currentAuthorizationState = .authorized
            }
            return currentAuthorizationState
        }
    }

    func deliver(_ alert: FleetAlert) async throws {
        let shouldFail = lock.withLock {
            storedDeliveryAttemptCount += 1
            if deliveryFailuresRemaining > 0 {
                deliveryFailuresRemaining -= 1
                return true
            }
            return false
        }
        if shouldFail {
            throw FakeError.deliveryFailed
        }
        lock.withLock { storedDeliveredAlerts.append(alert) }
    }

    func setAuthorizationState(_ state: NotificationAuthorizationState) {
        lock.withLock { currentAuthorizationState = state }
    }
}

nonisolated private final class MemoryNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var episodeIDs: Set<String> = []

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { episodeIDs.contains(episodeID) }
    }

    func record(_ episodeID: String) {
        _ = lock.withLock { episodeIDs.insert(episodeID) }
    }
}
