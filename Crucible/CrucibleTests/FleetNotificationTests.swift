import Foundation
import Testing
import UserNotifications
@testable import Crucible

@MainActor
struct FleetNotificationTests {
    @Test("Important condition planner covers every required CLI condition with actionable identity and copy")
    func requiredConditionCopy() throws {
        let conditions = [
            condition(id: "stall", type: "stalled", actual: 720, bound: 600),
            condition(id: "time-soft", type: "time_soft_bound_exceeded", actual: 1_500, bound: 1_260),
            condition(id: "time-hard", type: "time_hard_bound_exceeded", actual: 3_603, bound: 3_600),
            condition(id: "token-soft", type: "token_soft_bound_exceeded", actual: 205_000, bound: 200_000),
            condition(id: "token-hard", type: "token_hard_bound_exceeded", actual: 260_000, bound: 250_000),
            condition(id: "source-stale", type: "source_stale", actual: 700, bound: 600),
        ]

        let alerts = ImportantConditionAlertPlanner.alerts(for: snapshot(conditions: conditions))

        #expect(alerts.map(\.episodeID) == ["stall", "time-soft", "time-hard", "token-soft", "token-hard"])
        #expect(alerts.map(\.title) == [
            "Lane stalled · MOB-1325",
            "Soft time limit exceeded · MOB-1325",
            "Hard time limit exceeded · MOB-1325",
            "Soft token limit exceeded · MOB-1325",
            "Hard token limit exceeded · MOB-1325",
        ])
        #expect(alerts.allSatisfy { $0.subtitle == "Controller fleet visibility · pro16" })
        #expect(alerts[0].body == "Implementation (implementer): No meaningful progress for 12m; stall threshold is 10m. Source 2025-07-16T11:26:40Z.")
        #expect(alerts[2].body == "Implementation (implementer): Running for 1h 0m; hard limit is 1h 0m. Source 2025-07-16T11:26:40Z.")
        #expect(alerts[3].body == "Implementation (implementer): Used 205.0K tokens; soft limit is 200.0K. Source 2025-07-16T11:26:40Z.")
        #expect(alerts[0].conditionType == "stalled")
        #expect(alerts[0].sourceTimestamp == snapshot(conditions: []).sourceTimestamp)
    }

    @Test("Production stalled condition plans and delivers actual and bound context")
    func productionStalledConditionDelivers() async throws {
        let harness = notificationHarness(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )
        #expect(state.notificationCoverageMode == .importantOnly)
        let productionCondition = condition(
            id: "CRUMAC-10:implement:stalled",
            type: "stalled",
            actual: 1_425,
            bound: 600
        )

        state.apply(try delivery(.healthy, conditions: [productionCondition]))
        await state.waitForNotificationEvaluation()

        let alert = try #require(harness.client.deliveredPayloads.first)
        #expect(alert.userInfo["condition_type"] == "stalled")
        #expect(alert.title == "Lane stalled · job-1")
        #expect(alert.subtitle == "Build fleet view · pro16")
        #expect(alert.body == "Implementation (implement): No meaningful progress for 23m; stall threshold is 10m. Source 2026-07-16T12:00:00Z.")
        #expect(harness.store.contains("CRUMAC-10:implement:stalled"))
    }

    @Test("Foreground notifications use visible and audible native presentation options")
    func foregroundPresentationOptions() {
        let options = NotificationPresentationPolicy.foregroundOptions
        #expect(options.contains(.banner))
        #expect(options.contains(.list))
        #expect(options.contains(.sound))
    }

    @Test("Fresh partial conditions remain actionable when the job record is truncated")
    func truncatedPartialConditionUsesTruthfulIDs() throws {
        let partial = FleetSnapshot(
            contractVersion: "1",
            sourceTimestamp: Date(timeIntervalSince1970: 1_752_665_200),
            queue: [],
            hosts: [],
            conditions: [condition(id: "truncated")]
        )

        let alert = try #require(ImportantConditionAlertPlanner.alerts(for: partial).first)
        #expect(alert.title == "Lane stalled · MOB-1325")
        #expect(alert.subtitle == "Job MOB-1325 · pro16")
        #expect(alert.body == "implementer: No meaningful progress for 12m; stall threshold is 10m. Source 2025-07-16T11:26:40Z.")
    }

    @Test("Notification routing payload round-trips every authoritative target field")
    func routingPayloadRoundTrip() throws {
        let alert = try #require(ImportantConditionAlertPlanner.alerts(
            for: snapshot(conditions: [condition(id: "payload", type: "time_hard_bound_exceeded")])
        ).first)

        let payload = alert.notificationPayload()
        let decoded = try #require(FleetAlertRoute(userInfo: payload.userInfo))
        #expect(decoded == alert.route)
        #expect(payload.episodeID == alert.episodeID)
        #expect(payload.requestIdentifier == "condition:payload")
        #expect(payload.title == alert.title)
        #expect(payload.subtitle == alert.subtitle)
        #expect(payload.body == alert.body)
        #expect(payload.userInfo == alert.route.userInfo)
        #expect(decoded.conditionEpisodeID == "payload")
        #expect(decoded.conditionType == "time_hard_bound_exceeded")
        #expect(decoded.hostID == "pro16")
        #expect(decoded.jobID == "MOB-1325")
        #expect(decoded.laneID == "implementer")
        #expect(decoded.sourceTimestamp == alert.sourceTimestamp)

        var incompletePayload = alert.route.userInfo
        incompletePayload.removeValue(forKey: "lane_id")
        #expect(FleetAlertRoute(userInfo: incompletePayload) == nil)
    }

    @Test("Major event alerts use their own unroutable discriminator and human failure copy")
    func eventPayload() {
        let alert = FleetEventAlert(event: event(
            seq: 19,
            id: "failed-launch-19",
            transitionClass: "failed_launch",
            reason: "the remote runner was unavailable",
            remediation: "retry_launch"
        ))
        let payload = alert.notificationPayload()

        #expect(payload.episodeID == "failed-launch-19")
        #expect(payload.requestIdentifier == "event:failed-launch-19")
        #expect(payload.title == "CRUMAC-8 failed to launch")
        #expect(payload.body == "CRUMAC-8 failed: the remote runner was unavailable. Next: retry launch.")
        #expect(payload.userInfo == [
            "kind": "event", "item_id": "CRUMAC-8", "transition_class": "failed_launch", "seq": "19",
        ])
        #expect(FleetAlertRoute(userInfo: payload.userInfo) == nil)
    }

    @Test("Notification delegate decodes a response and delivers it on MainActor")
    func delegateResponseBridge() async throws {
        let route = alertRoute()
        let delegate = CrucibleNotificationCenterDelegate()
        var receivedRoute: FleetAlertRoute?
        delegate.setResponseHandler { receivedRoute = $0 }

        await withCheckedContinuation { continuation in
            delegate.dispatchResponse(userInfo: route.userInfo) {
                continuation.resume()
            }
        }

        #expect(receivedRoute == route)
    }

    @Test("Notification response completion follows the MainActor route mutation")
    func responseCompletionFollowsRouteMutation() async {
        let route = alertRoute()
        let delegate = CrucibleNotificationCenterDelegate()
        let recorder = ThreadSafeEventRecorder()
        delegate.setResponseHandler { _ in recorder.record("route") }

        await withCheckedContinuation { continuation in
            delegate.dispatchResponse(userInfo: route.userInfo) {
                recorder.record("completion")
                continuation.resume()
            }
        }

        #expect(recorder.events == ["route", "completion"])
    }

    @Test("Notification response selects the exact lane and emits a dashboard request")
    func responseRoutesToExactLane() {
        let state = AppState(initialPresentation: FleetPresentation(
            snapshot: snapshot(conditions: []),
            freshness: .live(asOf: snapshot(conditions: []).sourceTimestamp),
            lastSuccessfulRefresh: snapshot(conditions: []).sourceTimestamp,
            errorMessage: nil,
            isPreviewData: false
        ))
        let route = alertRoute()

        state.handleNotificationResponse(route)

        #expect(state.selection == .lane(jobID: "MOB-1325", laneID: "implementer"))
        #expect(state.selectionDetail?.title == "Implementation")
        #expect(state.unresolvedNotificationTarget == nil)
        #expect(state.notificationNavigationRequest?.route == route)
    }

    @Test("A partial snapshot routes an exact present target and preserves its incomplete-data warning")
    func partialSnapshotRoutesPresentTarget() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        let route = FleetAlertRoute(
            conditionEpisodeID: "pending-route",
            conditionType: "no_progress_stall",
            hostID: "pro16",
            jobID: "job-1",
            laneID: "implement",
            sourceTimestamp: Date(timeIntervalSince1970: 1_752_665_200)
        )

        state.apply(try delivery(.incomplete, conditions: [condition(id: "partial-route")]))
        state.handleNotificationResponse(route)
        #expect(state.selection == .lane(jobID: "job-1", laneID: "implement"))
        #expect(state.selectedHostID == "pro16")
        #expect(state.unresolvedNotificationTarget == nil)
        #expect(state.presentation.errorMessage?.contains("incomplete") == true)

        state.apply(try delivery(.healthy, conditions: [condition(id: "complete-route")]))
        #expect(state.selection == .lane(jobID: "job-1", laneID: "implement"))
        #expect(state.unresolvedNotificationTarget == nil)

        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))
        #expect(state.selection == nil)
        #expect(state.selectedHostID == nil)
        #expect(state.unresolvedNotificationTarget?.route == route)
        #expect(state.unresolvedNotificationTarget?.reason == .targetUnavailable)

        state.selectHost("pro16")
        #expect(state.selection == .host(hostID: "pro16"))
        #expect(state.unresolvedNotificationTarget == nil)

        state.apply(try delivery(
            .healthy,
            conditions: [condition(id: "target-returned")],
            generatedAt: "2026-07-16T12:02:05.000Z",
            sourceObservedAt: "2026-07-16T12:02:00.000Z"
        ))
        #expect(state.selection == .host(hostID: "pro16"))
        #expect(state.unresolvedNotificationTarget == nil)
    }

    @Test("A genuinely absent notification target remains explicit under partial data")
    func absentPartialTargetIsUnresolved() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        let route = FleetAlertRoute(
            conditionEpisodeID: "absent-route",
            conditionType: "no_progress_stall",
            hostID: "studio2",
            jobID: "missing-job",
            laneID: "missing-lane",
            sourceTimestamp: Date(timeIntervalSince1970: 1_752_665_200)
        )

        state.handleNotificationResponse(route)
        state.apply(try delivery(.incomplete, conditions: [condition(id: "other-target")]))

        #expect(state.selection == nil)
        #expect(state.selectedHostID == nil)
        #expect(state.unresolvedNotificationTarget?.route == route)
        #expect(state.unresolvedNotificationTarget?.reason == .partialSnapshot)
        #expect(state.presentation.errorMessage?.contains("incomplete") == true)
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

        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["first"])
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
        #expect(harness.client.deliveredPayloads.isEmpty)
        #expect(!harness.store.contains("pending"))

        await state.requestNotificationAuthorization()
        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["pending"])
        #expect(harness.store.contains("pending"))

        state.apply(try delivery(.healthy, conditions: [condition(id: "pending")]))
        await state.waitForNotificationEvaluation()
        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["pending"])
    }

    @Test("All-major keeps an active condition eligible through explicit authorization")
    func allMajorPendingConditionDeliversAfterAuthorization() async throws {
        let suiteName = "all-major-pending-condition-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let harness = notificationHarness(authorizationState: .notDetermined)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator,
            coverageModeDefaults: defaults
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "all-major-pending")]))
        await state.waitForNotificationEvaluation()
        #expect(harness.client.deliveredPayloads.isEmpty)

        await state.requestNotificationAuthorization()

        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["all-major-pending"])
        #expect(harness.store.contains("all-major-pending"))
    }

    @Test("Returning from System Settings refreshes permission, clears obsolete errors, and delivers active conditions")
    func settingsActivationRefreshesAuthorization() async throws {
        let client = FakeSystemNotificationClient(
            authorizationState: .notDetermined,
            authorizationRequestFailuresRemaining: 1
        )
        let coordinator = FleetNotificationCoordinator(
            client: client,
            episodeStore: MemoryNotificationEpisodeStore()
        )
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: coordinator
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "settings-active")]))
        await state.waitForNotificationEvaluation()
        await state.requestNotificationAuthorization()
        #expect(state.notificationAuthorizationState == .notDetermined)
        #expect(state.notificationErrorMessage?.contains("permission") == true)

        client.setAuthorizationState(.authorized)
        await state.notificationSettingsDidBecomeActive()

        #expect(state.notificationAuthorizationState == .authorized)
        #expect(state.notificationErrorMessage == nil)
        #expect(client.deliveredPayloads.map(\.episodeID) == ["settings-active"])
    }

    @Test("A permission retry evaluates the latest snapshot after an active condition resolves")
    func permissionRetryUsesLatestResolvedSnapshot() async throws {
        let client = FakeSystemNotificationClient(
            authorizationState: .authorized,
            authorizationResponses: [
                StubAuthorizationResponse(state: .notDetermined, delay: .milliseconds(200)),
                StubAuthorizationResponse(state: .authorized),
                StubAuthorizationResponse(state: .authorized),
            ]
        )
        let store = MemoryNotificationEpisodeStore()
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(client: client, episodeStore: store)
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "resolved-during-retry")]))
        await waitUntil { client.authorizationStateRequestCount == 1 }
        let settingsRetry = Task { await state.notificationSettingsDidBecomeActive() }

        // A non-serialized retry can complete and capture the active snapshot while
        // the first notification evaluation is still awaiting its older result.
        try await Task.sleep(for: .milliseconds(50))
        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))

        await settingsRetry.value
        await state.waitForNotificationEvaluation()

        #expect(client.deliveredPayloads.isEmpty)
        #expect(!store.contains("resolved-during-retry"))
    }

    @Test("An authorized older evaluation cannot alert after a newer snapshot resolves its condition")
    func authorizedEvaluationUsesLatestResolvedSnapshot() async throws {
        let client = FakeSystemNotificationClient(
            authorizationState: .authorized,
            authorizationResponses: [
                StubAuthorizationResponse(state: .authorized, delay: .milliseconds(200)),
                StubAuthorizationResponse(state: .authorized),
                StubAuthorizationResponse(state: .authorized),
            ]
        )
        let store = MemoryNotificationEpisodeStore()
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(client: client, episodeStore: store)
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "resolved-while-authorized")]))
        await waitUntil { client.authorizationStateRequestCount == 1 }
        let settingsRetry = Task { await state.notificationSettingsDidBecomeActive() }

        try await Task.sleep(for: .milliseconds(50))
        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))

        await settingsRetry.value
        await state.waitForNotificationEvaluation()

        #expect(client.deliveredPayloads.isEmpty)
        #expect(!store.contains("resolved-while-authorized"))
    }

    @Test("Permission recovery cannot deliver a condition resolved during its delivery evaluation")
    func permissionRecoveryEvaluationUsesLatestSnapshot() async throws {
        let client = FakeSystemNotificationClient(
            authorizationState: .authorized,
            authorizationResponses: [
                StubAuthorizationResponse(state: .notDetermined),
                StubAuthorizationResponse(state: .authorized),
                StubAuthorizationResponse(state: .authorized, delay: .milliseconds(200)),
                StubAuthorizationResponse(state: .authorized),
            ]
        )
        let store = MemoryNotificationEpisodeStore()
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(client: client, episodeStore: store)
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "resolved-during-recovery")]))
        await state.waitForNotificationEvaluation()
        #expect(client.deliveredPayloads.isEmpty)

        let settingsRetry = Task { await state.notificationSettingsDidBecomeActive() }
        await waitUntil { client.authorizationStateRequestCount == 3 }
        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))

        await settingsRetry.value
        await state.waitForNotificationEvaluation()

        #expect(client.deliveredPayloads.isEmpty)
        #expect(!store.contains("resolved-during-recovery"))
    }

    @Test("Overlapping authorization refreshes cannot let an older response win")
    func authorizationRefreshesRemainOrdered() async {
        let client = FakeSystemNotificationClient(
            authorizationState: .unknown,
            authorizationResponses: [
                StubAuthorizationResponse(state: .denied, delay: .milliseconds(150)),
                StubAuthorizationResponse(state: .authorized),
            ]
        )
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: client,
                episodeStore: MemoryNotificationEpisodeStore()
            )
        )

        let olderRefresh = Task { await state.refreshNotificationAuthorizationState() }
        await waitUntil { client.authorizationStateRequestCount == 1 }
        let newerRefresh = Task { await state.refreshNotificationAuthorizationState() }
        await olderRefresh.value
        await newerRefresh.value

        #expect(client.authorizationStateRequestCount == 2)
        #expect(state.notificationAuthorizationState == .authorized)
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

        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["partial"])
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

        #expect(harness.client.deliveredPayloads.isEmpty)
    }

    @Test("Partial, stale, error, and out-of-order snapshots never prune an active delivered episode")
    func nonAuthoritativeSnapshotsDoNotPrune() async throws {
        let harness = notificationHarness(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: harness.coordinator
        )

        state.apply(try delivery(.healthy, conditions: [condition(id: "retained")]))
        await state.waitForNotificationEvaluation()
        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["retained"])

        state.apply(try delivery(.stale, conditions: []))
        state.apply(try LiveFleetFixture.failed.delivery)
        state.apply(try delivery(
            .healthy,
            conditions: [],
            generatedAt: "2026-07-16T11:59:05.000Z",
            sourceObservedAt: "2026-07-16T11:59:00.000Z"
        ))
        state.apply(try delivery(
            .incomplete,
            conditions: [condition(id: "retained")],
            generatedAt: "2026-07-16T12:02:05.000Z",
            sourceObservedAt: "2026-07-16T12:02:00.000Z"
        ))
        await state.waitForNotificationEvaluation()

        #expect(harness.store.contains("retained"))
        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["retained"])
    }

    @Test("Denial and scheduling failures do not consume an episode")
    func denialAndFailureRetry() async {
        let deniedHarness = notificationHarness(authorizationState: .denied)
        let active = snapshot(conditions: [condition(id: "denied")])

        let deniedResult = await deniedHarness.coordinator.process(
            active,
            isAuthoritativeComplete: true
        )
        #expect(deniedResult.authorizationState == .denied)
        #expect(!deniedHarness.store.contains("denied"))

        deniedHarness.client.setAuthorizationState(.authorized)
        let authorizedResult = await deniedHarness.coordinator.process(
            active,
            isAuthoritativeComplete: true
        )
        #expect(authorizedResult.deliveredEpisodeIDs == ["denied"])
        #expect(deniedHarness.store.contains("denied"))

        let failingHarness = notificationHarness(
            authorizationState: .authorized,
            deliveryFailuresRemaining: 1
        )
        let retrySnapshot = snapshot(conditions: [condition(id: "retry")])
        let failedResult = await failingHarness.coordinator.process(
            retrySnapshot,
            isAuthoritativeComplete: true
        )
        #expect(failedResult.deliveryErrors.count == 1)
        #expect(!failingHarness.store.contains("retry"))

        let retriedResult = await failingHarness.coordinator.process(
            retrySnapshot,
            isAuthoritativeComplete: true
        )
        #expect(retriedResult.deliveredEpisodeIDs == ["retry"])
        #expect(failingHarness.client.deliveryAttemptCount == 2)
        #expect(failingHarness.store.contains("retry"))
    }

    @Test("Delivered condition episodes deduplicate across refreshes")
    func unchangedEpisodeDeduplicates() async {
        let harness = notificationHarness(authorizationState: .authorized)
        let active = snapshot(conditions: [condition(id: "same-episode")])

        _ = await harness.coordinator.process(active, isAuthoritativeComplete: true)
        _ = await harness.coordinator.process(active, isAuthoritativeComplete: true)

        #expect(harness.client.deliveredPayloads.map(\.episodeID) == ["same-episode"])
    }

    @Test("More than 256 active episodes remain deduplicated until a complete snapshot prunes inactive identities")
    func persistenceFollowsAuthoritativeLifecycle() async {
        let suiteName = "CrucibleTests.Notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "episodes"
        let store = UserDefaultsNotificationEpisodeStore(defaults: defaults, key: key)
        let client = FakeSystemNotificationClient(authorizationState: .authorized)
        let coordinator = FleetNotificationCoordinator(client: client, episodeStore: store)
        let allConditions = (0..<300).map { condition(id: "episode-\($0)") }
        let survivingConditions = Array(allConditions.suffix(20))

        _ = await coordinator.process(
            snapshot(conditions: allConditions),
            isAuthoritativeComplete: true
        )
        _ = await coordinator.process(
            snapshot(conditions: allConditions),
            isAuthoritativeComplete: true
        )
        #expect(client.deliveredPayloads.count == 300)

        _ = await coordinator.process(
            snapshot(conditions: survivingConditions),
            isAuthoritativeComplete: false
        )
        #expect(store.contains("episode-0"))
        #expect(client.deliveredPayloads.count == 300)

        _ = await coordinator.process(
            snapshot(conditions: survivingConditions),
            isAuthoritativeComplete: true
        )
        #expect(!store.contains("episode-0"))
        #expect(store.contains("episode-299"))
        #expect(defaults.stringArray(forKey: key)?.count == 20)
    }

    @Test("Persisted delivery identities never evict successful records to admit new episodes")
    func persistenceUsesNoEvictionAdmission() {
        let suiteName = "CrucibleTests.Notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "episodes"
        defaults.set(
            ["legacy-0", "legacy-1", "legacy-0", "legacy-2", "legacy-3"],
            forKey: key
        )

        let store = UserDefaultsNotificationEpisodeStore(defaults: defaults, key: key, capacity: 3)
        #expect(defaults.stringArray(forKey: key) == ["legacy-0", "legacy-2", "legacy-3"])
        #expect(store.admit("new") == .capacityReached)
        #expect(defaults.stringArray(forKey: key) == ["legacy-0", "legacy-2", "legacy-3"])

        store.reconcile(authoritativeActiveEpisodeIDs: ["legacy-2", "legacy-3", "new"])
        #expect(defaults.stringArray(forKey: key) == ["legacy-2", "legacy-3"])
        #expect(store.admit("new") == .admitted)
        #expect(store.admit("overflow") == .capacityReached)
        store.abandon("new")
        #expect(store.admit("overflow") == .admitted)
        store.abandon("overflow")
        #expect(store.admit("new") == .admitted)
        store.record("new")
        #expect(defaults.stringArray(forKey: key) == ["legacy-2", "legacy-3", "new"])

        #expect(store.admit("new") == .alreadyTracked)
        #expect(store.admit("overflow") == .capacityReached)
    }

    @Test("Capacity overflow stays retryable without evicting or repeating successful alerts")
    func capacityOverflowDoesNotRepeatDeliveredEpisodes() async {
        let suiteName = "CrucibleTests.Notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsNotificationEpisodeStore(
            defaults: defaults,
            key: "episodes",
            capacity: 3
        )
        let client = FakeSystemNotificationClient(authorizationState: .authorized)
        let coordinator = FleetNotificationCoordinator(client: client, episodeStore: store)
        let activeConditions = (0..<4).map { condition(id: "episode-\($0)") }
        let activeSnapshot = snapshot(conditions: activeConditions)

        let firstResult = await coordinator.process(activeSnapshot, isAuthoritativeComplete: true)
        #expect(firstResult.deliveredEpisodeIDs == ["episode-0", "episode-1", "episode-2"])
        #expect(firstResult.deliveryErrors.count == 1)
        #expect(firstResult.deliveryErrors.first?.contains("episode-3") == true)
        #expect(firstResult.deliveryErrors.first?.contains("will retry") == true)
        #expect(client.deliveryAttemptCount == 3)
        #expect(client.deliveredPayloads.map(\.episodeID) == ["episode-0", "episode-1", "episode-2"])
        #expect(store.contains("episode-0"))
        #expect(store.contains("episode-1"))
        #expect(store.contains("episode-2"))
        #expect(!store.contains("episode-3"))

        let retryResult = await coordinator.process(activeSnapshot, isAuthoritativeComplete: true)
        #expect(retryResult.deliveredEpisodeIDs.isEmpty)
        #expect(retryResult.deliveryErrors.count == 1)
        #expect(retryResult.deliveryErrors.first?.contains("episode-3") == true)
        #expect(retryResult.deliveryErrors.first?.contains("will retry") == true)
        #expect(client.deliveryAttemptCount == 3)
        #expect(client.deliveredPayloads.map(\.episodeID) == ["episode-0", "episode-1", "episode-2"])
        #expect(defaults.stringArray(forKey: "episodes") == [
            "episode-0", "episode-1", "episode-2",
        ])

        let overflowOnlySnapshot = snapshot(conditions: [activeConditions[3]])
        let recoveredResult = await coordinator.process(
            overflowOnlySnapshot,
            isAuthoritativeComplete: true
        )
        #expect(recoveredResult.deliveredEpisodeIDs == ["episode-3"])
        #expect(recoveredResult.deliveryErrors.isEmpty)
        #expect(client.deliveryAttemptCount == 4)
        #expect(client.deliveredPayloads.map(\.episodeID) == [
            "episode-0", "episode-1", "episode-2", "episode-3",
        ])
        #expect(!store.contains("episode-0"))
        #expect(!store.contains("episode-1"))
        #expect(!store.contains("episode-2"))
        #expect(store.contains("episode-3"))
        #expect(defaults.stringArray(forKey: "episodes") == ["episode-3"])
    }

    @Test("FIFO event delivery history evicts the oldest identity without wedging admission")
    func fifoEventStoreEviction() throws {
        let suiteName = "event-store-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FIFOEventDeliveryStore(defaults: defaults, key: "events", capacity: 3)

        for index in 0..<5 {
            let eventID = "event-\(index)"
            #expect(store.admit(eventID) == .admitted)
            store.record(eventID)
        }

        #expect(defaults.stringArray(forKey: "events") == ["event-2", "event-3", "event-4"])
        #expect(!store.contains("event-0"))
        #expect(store.contains("event-4"))
        #expect(store.admit("event-4") == .alreadyTracked)
        #expect(store.admit("event-5") == .admitted)
        store.record("event-5")
        #expect(defaults.stringArray(forKey: "events") == ["event-3", "event-4", "event-5"])
    }

    @Test("All-major delivers condition and all feed alerts without repeating either path")
    func allMajorEndToEnd() async throws {
        let suiteName = "all-major-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let major = event(seq: 11, id: "major-11", itemID: "CRUMAC-8", host: "pro16")
        let important = event(
            seq: 12,
            id: "important-12",
            itemID: "CRUMAC-8",
            importance: .important,
            transitionClass: "review",
            reason: "review evidence is incomplete"
        )
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 10, events: []))),
                (10, .events(eventsEnvelope(cursor: 12, events: [major, important]))),
                (12, .events(eventsEnvelope(cursor: 12, events: [major]))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let eventStore = MemoryNotificationEpisodeStore()
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: eventStore
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(cursorStore.cursorSeq() == 10)

        await state.pollMajorEventsNow()
        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == ["major-11", "important-12"])
        #expect(notificationClient.deliveredPayloads[0].title == "Job CRUMAC-8 launched on pro16")
        #expect(notificationClient.deliveredPayloads[0].userInfo == [
            "kind": "event", "item_id": "CRUMAC-8", "transition_class": "launched", "seq": "11",
        ])
        #expect(eventStore.contains("important-12"))
        #expect(cursorStore.cursorSeq() == 12)

        state.apply(try delivery(.healthy, conditions: [condition(
            id: "condition-all-major",
            type: "token_hard_bound_exceeded",
            actual: 260_000,
            bound: 250_000
        )]))
        await state.waitForNotificationEvaluation()
        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == [
            "major-11", "important-12", "condition-all-major",
        ])

        state.apply(try delivery(
            .healthy,
            conditions: [condition(
                id: "condition-all-major",
                type: "token_hard_bound_exceeded",
                actual: 260_000,
                bound: 250_000
            )],
            generatedAt: "2026-07-16T12:01:05.000Z",
            sourceObservedAt: "2026-07-16T12:01:00.000Z"
        ))
        await state.waitForNotificationEvaluation()

        await state.pollMajorEventsNow()
        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == [
            "major-11", "important-12", "condition-all-major",
        ])
        #expect(cursorStore.cursorSeq() == 12)
        #expect(await client.eventCallCursors() == [nil, 10, 12])
    }

    @Test("All-major launch resumes a persisted cursor and delivers the backlog")
    func persistedCursorResumesAfterLaunch() async throws {
        let suiteName = "persisted-cursor-launch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        cursorStore.store(7)
        let backlog = event(seq: 8, id: "backlog-8", importance: .important, transitionClass: "failed_launch")
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (7, .events(eventsEnvelope(cursor: 8, events: [backlog]))),
                (nil, .events(eventsEnvelope(cursor: 99, events: []))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()

        #expect(await client.eventCallCursors() == [7])
        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == ["backlog-8"])
        #expect(cursorStore.cursorSeq() == 8)
    }

    @Test("Explicit all-major re-entry reseeds past events accumulated while opted out")
    func allMajorReentryReseedsPersistedCursor() async throws {
        let suiteName = "persisted-cursor-toggle-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        cursorStore.store(4)
        let backlog = event(seq: 5, id: "backlog-5")
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (4, .events(eventsEnvelope(cursor: 5, events: [backlog]))),
                (nil, .events(eventsEnvelope(cursor: 99, events: []))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        state.setNotificationCoverageMode(.importantOnly)
        state.setNotificationCoverageMode(.allMajorChanges)
        await state.pollMajorEventsNow()

        #expect(await client.eventCallCursors() == [nil])
        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(cursorStore.cursorSeq() == 99)
    }

    @Test("An inclusive boundary row at the seeded cursor is never delivered")
    func seededCursorBoundaryIsExclusive() async throws {
        let suiteName = "seed-boundary-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let boundary = event(seq: 10, id: "boundary-10")
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 10, events: []))),
                (10, .events(eventsEnvelope(cursor: 10, events: [boundary]))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let eventStore = MemoryNotificationEpisodeStore()
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: eventStore
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(await client.eventCallCursors() == [nil, 10])
        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(!eventStore.contains("boundary-10"))
        #expect(cursorStore.cursorSeq() == 10)
    }

    @Test("A cursor-expired response reseeds from tail without delivering history")
    func cursorExpiredReseeds() async throws {
        let suiteName = "cursor-expired-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 5, events: [event(seq: 5, id: "old")]))),
                (5, eventError(code: "cursor_expired")),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(cursorStore.cursorSeq() == 5)
        #expect(await client.eventCallCursors() == [nil, 5, nil])
    }

    @Test("An invalid cursor response reseeds from tail without retrying the unusable cursor")
    func invalidCursorReseeds() async throws {
        let suiteName = "invalid-cursor-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 5, events: []))),
                (5, eventError(code: "invalid_cursor")),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(cursorStore.cursorSeq() == 5)
        #expect(await client.eventCallCursors() == [nil, 5, nil])
    }

    @Test("Notification re-authorization reseeds instead of replaying events accumulated while blocked")
    func reauthorizationReseeds() async throws {
        let suiteName = "reauthorization-event-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let pending = event(seq: 1, id: "pending-while-denied")
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 0, events: []))),
                (0, .events(eventsEnvelope(cursor: 1, events: [pending]))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .denied)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.refreshNotificationAuthorizationState()
        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()
        #expect(cursorStore.cursorSeq() == 0)
        #expect(notificationClient.deliveredPayloads.isEmpty)

        notificationClient.setAuthorizationState(.authorized)
        await state.notificationSettingsDidBecomeActive()
        await state.pollMajorEventsNow()

        #expect(cursorStore.cursorSeq() == 0)
        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(await client.eventCallCursors() == [nil, 0, nil])
    }

    @Test("An oversized event backlog reseeds from tail without a notification storm")
    func oversizedBacklogReseeds() async throws {
        let suiteName = "oversized-event-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let seedCursor = AppState.maximumEventsPerPoll + 1
        let backlog = (1...AppState.maximumEventsPerPoll + 1).map {
            event(seq: seedCursor + $0, id: "backlog-\($0)")
        }
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: seedCursor, events: []))),
                (seedCursor, .events(eventsEnvelope(cursor: seedCursor + backlog.count, events: backlog))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(notificationClient.deliveredPayloads.isEmpty)
        #expect(cursorStore.cursorSeq() == seedCursor)
        #expect(await client.eventCallCursors() == [nil, seedCursor, nil])
    }

    @Test("An output-too-large incremental poll reseeds from tail instead of wedging")
    func outputTooLargeReseeds() async throws {
        let suiteName = "output-too-large-event-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        cursorStore.store(7)
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 20, events: []))),
            ]),
            eventErrors: [7: .outputTooLarge(1_048_576)]
        )
        let notificationClient = FakeSystemNotificationClient(authorizationState: .authorized)
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()

        #expect(await client.eventCallCursors() == [7, nil])
        #expect(cursorStore.cursorSeq() == 20)
        #expect(notificationClient.deliveredPayloads.isEmpty)
    }

    @Test("Source-invalid errors retain the still-valid cursor for cadence-backed retry")
    func sourceInvalidDoesNotAdvance() async throws {
        let suiteName = "event-error-tests-source-invalid-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 7, events: []))),
                (7, eventError(code: "source_invalid")),
            ])
        )
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: FakeSystemNotificationClient(authorizationState: .authorized),
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(cursorStore.cursorSeq() == 7)
        #expect(await client.eventCallCursors() == [nil, 7])
    }

    @Test("Persistent seed failures become visible, back off, and clear after recovery")
    func persistentSeedFailureEscalatesAndRecovers() async throws {
        let suiteName = "event-seed-failure-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliverySequences: [nil: [
                eventError(code: "source_invalid"),
                eventError(code: "source_invalid"),
                eventError(code: "source_invalid"),
                .events(eventsEnvelope(cursor: 9, events: [])),
            ]]
        )
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: FakeSystemNotificationClient(authorizationState: .authorized),
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: MemoryNotificationEpisodeStore()
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        for _ in 0..<3 { await state.pollMajorEventsNow() }

        #expect(state.notificationErrorMessage == "Live event feed unavailable. Crucible will retry automatically.")
        #expect(await client.eventCallCursors() == [nil, nil, nil])

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()
        #expect(await client.eventCallCursors() == [nil, nil, nil])

        await state.pollMajorEventsNow()

        #expect(state.notificationErrorMessage == nil)
        #expect(cursorStore.cursorSeq() == 9)
        #expect(await client.eventCallCursors() == [nil, nil, nil, nil])
    }

    @Test("A delivery failure stops the batch at the failed event and resumes with ID deduplication")
    func partialEventDeliveryFailure() async throws {
        let suiteName = "partial-event-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NotificationCoverageMode.allMajorChanges.store(in: defaults)
        let first = event(seq: 1, id: "major-1")
        let important = event(seq: 2, id: "important-2", importance: .important, transitionClass: "review")
        let failed = event(seq: 3, id: "major-3", transitionClass: "merged")
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            eventDeliveries: scriptedEvents([
                (nil, .events(eventsEnvelope(cursor: 0, events: []))),
                (0, .events(eventsEnvelope(cursor: 3, events: [first, important, failed]))),
                (1, .events(eventsEnvelope(cursor: 3, events: [important, failed]))),
            ])
        )
        let notificationClient = FakeSystemNotificationClient(
            authorizationState: .authorized,
            deliveryFailureAttempts: [2]
        )
        let cursorStore = EventsCursorStore(defaults: defaults, key: "cursor")
        let eventStore = MemoryNotificationEpisodeStore()
        let state = AppState(
            initialPresentation: .productionUnavailable,
            notificationCoordinator: FleetNotificationCoordinator(
                client: notificationClient,
                episodeStore: MemoryNotificationEpisodeStore(),
                eventStore: eventStore
            ),
            eventsClient: client,
            eventsCursorStore: cursorStore,
            coverageModeDefaults: defaults
        )

        await state.pollMajorEventsNow()
        await state.pollMajorEventsNow()

        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == ["major-1"])
        #expect(cursorStore.cursorSeq() == 1)
        #expect(!eventStore.contains("major-3"))
        #expect(state.notificationErrorMessage != nil)

        await state.pollMajorEventsNow()

        #expect(notificationClient.deliveredPayloads.map(\.episodeID) == [
            "major-1", "important-2", "major-3",
        ])
        #expect(notificationClient.deliveryAttemptCount == 4)
        #expect(cursorStore.cursorSeq() == 3)
        #expect(await client.eventCallCursors() == [nil, 0, 1])
        #expect(state.notificationErrorMessage == nil)
    }

    private func event(
        seq: Int,
        id: String,
        itemID: String = "CRUMAC-8",
        importance: LiveFleetEventV1.Importance = .major,
        transitionClass: String = "launched",
        host: String? = nil,
        reason: String? = nil,
        remediation: String? = nil
    ) -> LiveFleetEventV1 {
        LiveFleetEventV1(
            schema: "crucible.live-fleet.transition.v1",
            seq: seq,
            recordedAt: Date(timeIntervalSince1970: 1_752_912_060 + Double(seq)),
            queueDirectory: "/var/tmp/crucible/queue",
            id: id,
            transitionClass: transitionClass,
            itemID: itemID,
            attemptID: "01",
            toState: nil,
            action: nil,
            host: host,
            reason: reason,
            failureClass: nil,
            remediation: remediation,
            importance: importance
        )
    }

    private func eventsEnvelope(
        cursor: Int,
        events: [LiveFleetEventV1]
    ) -> LiveFleetEventsEnvelopeV1 {
        LiveFleetEventsEnvelopeV1(
            schema: "crucible.live-fleet.events.v1",
            contractVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_752_912_300),
            cursor: LiveFleetEventsCursorV1(seq: cursor),
            events: events
        )
    }

    private func eventError(code: String) -> LiveFleetEventsDelivery {
        .error(LiveFleetErrorEnvelopeV1(
            schema: "crucible.live-fleet.error.v1",
            contractVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_752_912_300),
            error: LiveFleetErrorV1(
                code: code,
                kind: .failed,
                message: "event cursor expired",
                retryable: true,
                source: "transitions-ledger"
            )
        ))
    }

    private func scriptedEvents(
        _ entries: [(Int?, LiveFleetEventsDelivery)]
    ) -> [Int?: LiveFleetEventsDelivery] {
        Dictionary(uniqueKeysWithValues: entries)
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
        let lane = LaneSnapshot(
            id: "implementer",
            name: "Implementation",
            state: .active,
            currentStage: "Implement",
            elapsedSeconds: 720,
            lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-720),
            retryCount: 0,
            restartCount: 0,
            recoverableFailures: [],
            tokenUse: 10_000,
            tokenBounds: TokenBounds(soft: 200_000, hard: 250_000),
            timeBounds: TimeBounds(softSeconds: 1_260, hardSeconds: 3_600)
        )
        let job = JobSnapshot(
            id: "MOB-1325",
            hostID: "pro16",
            title: "Controller fleet visibility",
            state: .active,
            currentStage: "Implement",
            elapsedSeconds: 720,
            lastMeaningfulProgressAt: sourceTimestamp.addingTimeInterval(-720),
            retryCount: 0,
            restartCount: 0,
            recoverableFailures: [],
            tokenUse: 10_000,
            tokenBounds: TokenBounds(soft: nil, hard: nil),
            timeBounds: TimeBounds(softSeconds: nil, hardSeconds: nil),
            lanes: [lane]
        )
        let host = HostSnapshot(
            id: "pro16",
            displayName: "pro16",
            condition: .busy,
            activeLaneCount: 1,
            laneCapacity: 10,
            jobs: [job]
        )
        return FleetSnapshot(
            contractVersion: "1",
            sourceTimestamp: sourceTimestamp,
            queue: [],
            hosts: [host],
            conditions: conditions
        )
    }

    private func alertRoute() -> FleetAlertRoute {
        FleetAlertRoute(
            conditionEpisodeID: "route",
            conditionType: "no_progress_stall",
            hostID: "pro16",
            jobID: "MOB-1325",
            laneID: "implementer",
            sourceTimestamp: Date(timeIntervalSince1970: 1_752_665_200)
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

    private func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for asynchronous notification test state")
                return
            }
            await Task.yield()
        }
    }

    @Test("Coverage mode persists across app state instances and defaults to important-only")
    func coverageModePersistence() throws {
        let suiteName = "coverage-mode-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppState(
            initialPresentation: .productionUnavailable,
            coverageModeDefaults: defaults
        )
        #expect(first.notificationCoverageMode == .importantOnly)

        first.setNotificationCoverageMode(.allMajorChanges)
        #expect(first.notificationCoverageMode == .allMajorChanges)

        let second = AppState(
            initialPresentation: .productionUnavailable,
            coverageModeDefaults: defaults
        )
        #expect(second.notificationCoverageMode == .allMajorChanges)

        defaults.set("garbage", forKey: NotificationCoverageMode.defaultsKey)
        let third = AppState(
            initialPresentation: .productionUnavailable,
            coverageModeDefaults: defaults
        )
        #expect(third.notificationCoverageMode == .importantOnly)
    }
}

@MainActor
private struct NotificationHarness {
    let client: FakeSystemNotificationClient
    let store: MemoryNotificationEpisodeStore
    let coordinator: FleetNotificationCoordinator
}

nonisolated private final class FakeSystemNotificationClient: SystemNotificationClient, @unchecked Sendable {
    enum FakeError: Error { case deliveryFailed, authorizationRequestFailed }

    private let lock = NSLock()
    private var currentAuthorizationState: NotificationAuthorizationState
    private var deliveryFailuresRemaining: Int
    private var deliveryFailureAttempts: Set<Int>
    private var authorizationRequestFailuresRemaining: Int
    private var authorizationResponses: [StubAuthorizationResponse]
    private var storedRequestCount = 0
    private var storedAuthorizationStateRequestCount = 0
    private var storedDeliveryAttemptCount = 0
    private var storedDeliveredPayloads: [NotificationPayload] = []

    var requestCount: Int { lock.withLock { storedRequestCount } }
    var authorizationStateRequestCount: Int { lock.withLock { storedAuthorizationStateRequestCount } }
    var deliveryAttemptCount: Int { lock.withLock { storedDeliveryAttemptCount } }
    var deliveredPayloads: [NotificationPayload] { lock.withLock { storedDeliveredPayloads } }

    init(
        authorizationState: NotificationAuthorizationState,
        deliveryFailuresRemaining: Int = 0,
        deliveryFailureAttempts: Set<Int> = [],
        authorizationRequestFailuresRemaining: Int = 0,
        authorizationResponses: [StubAuthorizationResponse] = []
    ) {
        currentAuthorizationState = authorizationState
        self.deliveryFailuresRemaining = deliveryFailuresRemaining
        self.deliveryFailureAttempts = deliveryFailureAttempts
        self.authorizationRequestFailuresRemaining = authorizationRequestFailuresRemaining
        self.authorizationResponses = authorizationResponses
    }

    func authorizationState() async -> NotificationAuthorizationState {
        let response = lock.withLock {
            storedAuthorizationStateRequestCount += 1
            return authorizationResponses.isEmpty ? nil : authorizationResponses.removeFirst()
        }
        guard let response else { return lock.withLock { currentAuthorizationState } }
        if response.delay > .zero {
            try? await Task.sleep(for: response.delay)
        }
        return response.state
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        try lock.withLock {
            storedRequestCount += 1
            if authorizationRequestFailuresRemaining > 0 {
                authorizationRequestFailuresRemaining -= 1
                throw FakeError.authorizationRequestFailed
            }
            if currentAuthorizationState == .notDetermined {
                currentAuthorizationState = .authorized
            }
            return currentAuthorizationState
        }
    }

    func deliver(_ payload: NotificationPayload) async throws {
        let shouldFail = lock.withLock {
            storedDeliveryAttemptCount += 1
            if deliveryFailuresRemaining > 0 {
                deliveryFailuresRemaining -= 1
                return true
            }
            return deliveryFailureAttempts.contains(storedDeliveryAttemptCount)
        }
        if shouldFail {
            throw FakeError.deliveryFailed
        }
        lock.withLock { storedDeliveredPayloads.append(payload) }
    }

    func setAuthorizationState(_ state: NotificationAuthorizationState) {
        lock.withLock { currentAuthorizationState = state }
    }
}

nonisolated private struct StubAuthorizationResponse: Sendable {
    let state: NotificationAuthorizationState
    let delay: Duration

    init(
        state: NotificationAuthorizationState,
        delay: Duration = .zero
    ) {
        self.state = state
        self.delay = delay
    }
}

nonisolated private final class ThreadSafeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }

    func record(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

nonisolated private final class MemoryNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var episodeIDs: Set<String> = []
    private var admittedEpisodeIDs: Set<String> = []

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { episodeIDs.contains(episodeID) }
    }

    func admit(_ episodeID: String) -> NotificationEpisodeAdmission {
        lock.withLock {
            guard !episodeIDs.contains(episodeID),
                  !admittedEpisodeIDs.contains(episodeID) else { return .alreadyTracked }
            admittedEpisodeIDs.insert(episodeID)
            return .admitted
        }
    }

    func record(_ episodeID: String) {
        lock.withLock {
            _ = admittedEpisodeIDs.remove(episodeID)
            episodeIDs.insert(episodeID)
        }
    }

    func abandon(_ episodeID: String) {
        _ = lock.withLock { admittedEpisodeIDs.remove(episodeID) }
    }

    func reconcile(authoritativeActiveEpisodeIDs: Set<String>) {
        lock.withLock { episodeIDs.formIntersection(authoritativeActiveEpisodeIDs) }
    }

}
