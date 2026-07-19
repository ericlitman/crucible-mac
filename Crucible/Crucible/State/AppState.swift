import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let maximumEventsPerPoll = 100

    private(set) var presentation: FleetPresentation
    private(set) var selection: FleetSelection?
    private(set) var isRefreshing = false
    private(set) var visibleSurfaces: Set<FleetSurface> = []
    private(set) var notificationAuthorizationState: NotificationAuthorizationState = .unknown
    private(set) var notificationErrorMessage: String?
    private(set) var unresolvedNotificationTarget: UnresolvedNotificationTarget?
    private(set) var notificationNavigationRequest: NotificationNavigationRequest?
    private(set) var notificationCoverageMode: NotificationCoverageMode

    private let refreshCoordinator: FleetRefreshCoordinator?
    private let notificationCoordinator: FleetNotificationCoordinator?
    private let eventsClient: (any CrucibleCLIClient)?
    private let eventsCursorStore: EventsCursorStore?
    private var presentationReducer: FleetPresentationReducer
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var eventsPollTask: Task<Void, Never>?
    private var eventsRefreshTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var pollingStarted = false
    private var lastAcceptedFreshSnapshotForNotifications: FleetSnapshot?
    private var lastAcceptedFreshSnapshotIsAuthoritativeComplete = false
    private var notificationSnapshotRevision: UInt64 = 0
    private var activeNotificationTargetRoute: FleetAlertRoute?
    private let coverageModeDefaults: UserDefaults
    private var eventsSeedRequired: Bool
    private var eventsRevision: UInt64 = 0

    init(
        initialPresentation: FleetPresentation,
        refreshCoordinator: FleetRefreshCoordinator? = nil,
        notificationCoordinator: FleetNotificationCoordinator? = nil,
        eventsClient: (any CrucibleCLIClient)? = nil,
        eventsCursorStore: EventsCursorStore? = nil,
        automaticallyStarts: Bool = false,
        coverageModeDefaults: UserDefaults = .standard
    ) {
        self.coverageModeDefaults = coverageModeDefaults
        notificationCoverageMode = NotificationCoverageMode.stored(in: coverageModeDefaults)
        presentation = initialPresentation
        presentationReducer = FleetPresentationReducer(initialPresentation: initialPresentation)
        self.refreshCoordinator = refreshCoordinator
        self.notificationCoordinator = notificationCoordinator
        self.eventsClient = eventsClient
        self.eventsCursorStore = eventsCursorStore
        eventsSeedRequired = eventsCursorStore?.cursorSeq() == nil
        // Queue-first default: the spec keeps Queue as a persistent first-class
        // scope and forbids silently selecting the first host.
        selection = nil
        AppTelemetry.launched(previewData: initialPresentation.isPreviewData)

        if automaticallyStarts {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startPolling()
                await self.refreshNotificationAuthorizationState()
            }
        }
    }

    var snapshot: FleetSnapshot? { presentation.snapshot }

    var selectedHostID: String? {
        if unresolvedNotificationTarget != nil { return nil }
        // No implicit selection: with nothing selected the dashboard shows the
        // queue scope (the spec forbids silently selecting the first host).
        guard let selection else { return nil }
        switch selection {
        case let .host(hostID): return hostID
        case let .job(jobID), let .lane(jobID, _): return snapshot?.job(id: jobID)?.hostID
        }
    }

    var selectedHost: HostSnapshot? { snapshot?.host(id: selectedHostID) }

    /// The snapshot job for a job/lane selection that has no assigned host,
    /// so the content column can show that job's context instead of the queue.
    var selectedHostlessJob: JobSnapshot? {
        guard selectedHost == nil else { return nil }
        switch selection {
        case let .job(jobID), let .lane(jobID, _):
            guard let job = snapshot?.job(id: jobID), job.hostID == nil else { return nil }
            return job
        case .host, nil:
            return nil
        }
    }

    var selectionDetail: FleetSelectionDetail? { snapshot?.detail(for: selection) }

    /// AC-7: a selection whose entity cannot be resolved is retained with
    /// identity and a truthful reason, never silently replaced.
    var unresolvedSelection: UnresolvedSelection? {
        guard unresolvedNotificationTarget == nil,
              let selection,
              let snapshot,
              snapshot.detail(for: selection) == nil else { return nil }
        let reason: UnresolvedSelection.Reason
        switch selection {
        case let .job(jobID), let .lane(jobID, _):
            // .detailTruncated applies only when the queued JOB record itself
            // is missing. A lane absent from a supplied job record was simply
            // not in that detail — queue entries identify jobs, not lanes.
            if snapshot.job(id: jobID) == nil,
               snapshot.queue.contains(where: { $0.id == jobID }) {
                reason = presentation.snapshotIsPartial ? .detailTruncated : .absent
            } else {
                reason = presentation.snapshotIsPartial ? .partialSnapshot : .absent
            }
        case .host:
            reason = presentation.snapshotIsPartial ? .partialSnapshot : .absent
        }
        return UnresolvedSelection(selection: selection, reason: reason)
    }

    var pollInterval: TimeInterval {
        FleetRefreshCadence.interval(hasVisibleSurface: !visibleSurfaces.isEmpty)
    }

    func startPolling() {
        guard !pollingStarted, refreshCoordinator != nil || eventsClient != nil else { return }
        pollingStarted = true
        reschedulePolling()
        rescheduleEventsPolling()
        requestRefresh()
        requestEventsRefresh()
    }

    func stopPolling() {
        pollingStarted = false
        eventsRevision &+= 1
        pollTask?.cancel()
        pollTask = nil
        eventsPollTask?.cancel()
        eventsPollTask = nil
        eventsRefreshTask?.cancel()
        eventsRefreshTask = nil
    }

    func refreshNow() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard let refreshCoordinator else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isRefreshing = true
            defer {
                isRefreshing = false
                refreshTask = nil
            }
            do {
                apply(try await refreshCoordinator.refresh())
            } catch is CancellationError {
                return
            } catch {
                presentation = presentationReducer.reducingFailure(error, current: presentation)
            }
        }
        refreshTask = task
        await task.value
    }

    func selectHost(_ hostID: String) {
        select(.host(hostID: hostID))
    }

    func selectJob(_ jobID: String) {
        select(.job(jobID: jobID))
    }

    func selectLane(_ laneID: String, in jobID: String) {
        select(.lane(jobID: jobID, laneID: laneID))
    }

    func select(_ newSelection: FleetSelection) {
        activeNotificationTargetRoute = nil
        unresolvedNotificationTarget = nil
        setSelection(newSelection)
    }

    /// AC-6: persists the operator's coverage choice. Important-only evaluates
    /// snapshot conditions; all-major consumes the durable event feed instead.
    func setNotificationCoverageMode(_ mode: NotificationCoverageMode) {
        guard notificationCoverageMode != mode else { return }
        notificationCoverageMode = mode
        mode.store(in: coverageModeDefaults)
        eventsRevision &+= 1
        eventsRefreshTask?.cancel()
        eventsRefreshTask = nil
        if mode == .allMajorChanges {
            if eventsCursorStore?.cursorSeq() == nil {
                eventsSeedRequired = true
            }
            rescheduleEventsPolling()
            requestEventsRefresh()
        } else {
            eventsPollTask?.cancel()
            eventsPollTask = nil
        }
    }

    /// Returns to the Queue scope — the persistent first-class destination —
    /// clearing any entity selection.
    func selectQueue() {
        activeNotificationTargetRoute = nil
        unresolvedNotificationTarget = nil
        selection = nil
        AppTelemetry.selected(kind: "queue", identifier: "queue")
    }

    private func setSelection(_ newSelection: FleetSelection) {
        selection = newSelection
        switch newSelection {
        case let .host(hostID): AppTelemetry.selected(kind: "host", identifier: hostID)
        case let .job(jobID): AppTelemetry.selected(kind: "job", identifier: jobID)
        case let .lane(_, laneID): AppTelemetry.selected(kind: "lane", identifier: laneID)
        }
    }

    func menuBarDidAppear() {
        AppTelemetry.menuBarPresented()
        surfaceDidAppear(.menuBar)
    }

    func menuBarDidDisappear() {
        surfaceDidDisappear(.menuBar)
    }

    func dashboardRequested() {
        AppTelemetry.dashboardRequested()
    }

    func dashboardDidAppear() {
        AppTelemetry.dashboardPresented()
        surfaceDidAppear(.dashboard)
    }

    func dashboardDidDisappear() {
        surfaceDidDisappear(.dashboard)
    }

    func apply(_ delivery: LiveFleetDelivery) {
        let reduction = presentationReducer.reduce(delivery, current: presentation)
        presentation = reduction.presentation
        resolveActiveNotificationTargetIfNeeded()
        if let snapshot = reduction.acceptedFreshSnapshot {
            lastAcceptedFreshSnapshotForNotifications = snapshot
            let isAuthoritativeComplete = reduction.acceptedFreshSnapshotIsPartial == false
            lastAcceptedFreshSnapshotIsAuthoritativeComplete = isAuthoritativeComplete
            notificationSnapshotRevision &+= 1
            if notificationCoverageMode == .importantOnly {
                scheduleNotifications(
                    for: snapshot,
                    isAuthoritativeComplete: isAuthoritativeComplete,
                    revision: notificationSnapshotRevision
                )
            }
        }
    }

    func refreshNotificationAuthorizationState() async {
        let task = enqueueNotificationOperation { state, coordinator in
            state.notificationAuthorizationState = await coordinator.authorizationState()
        }
        await task?.value
    }

    func notificationSettingsDidBecomeActive() async {
        let task = enqueueNotificationOperation { state, coordinator in
            state.notificationErrorMessage = nil
            let priorAuthorization = state.notificationAuthorizationState
            state.notificationAuthorizationState = await coordinator.authorizationState()
            state.markEventsForReseedIfReauthorized(from: priorAuthorization)
            await state.deliverLatestAcceptedSnapshotIfAuthorized(using: coordinator)
        }
        await task?.value
        if eventsSeedRequired { requestEventsRefresh() }
    }

    func requestNotificationAuthorization() async {
        let task = enqueueNotificationOperation { state, coordinator in
            state.notificationErrorMessage = nil
            do {
                let priorAuthorization = state.notificationAuthorizationState
                state.notificationAuthorizationState = try await coordinator.requestAuthorization()
                state.markEventsForReseedIfReauthorized(from: priorAuthorization)
                await state.deliverLatestAcceptedSnapshotIfAuthorized(using: coordinator)
            } catch {
                state.notificationErrorMessage = "Notification permission could not be updated: \(error.localizedDescription)"
                state.notificationAuthorizationState = await coordinator.authorizationState()
            }
        }
        await task?.value
        if eventsSeedRequired { requestEventsRefresh() }
    }

    func waitForNotificationEvaluation() async {
        await notificationTask?.value
    }

    func pollMajorEventsNow() async {
        if let eventsRefreshTask {
            await eventsRefreshTask.value
            return
        }
        guard notificationCoverageMode == .allMajorChanges,
              eventsClient != nil,
              eventsCursorStore != nil,
              notificationCoordinator != nil else { return }

        let revision = eventsRevision
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.eventsRevision == revision { self.eventsRefreshTask = nil }
            }
            await self.performEventsRefresh(revision: revision)
        }
        eventsRefreshTask = task
        await task.value
    }

    func handleNotificationResponse(_ route: FleetAlertRoute) {
        notificationNavigationRequest = NotificationNavigationRequest(route: route)
        activeNotificationTargetRoute = route
        resolveNotificationTarget(route)
    }

    private func surfaceDidAppear(_ surface: FleetSurface) {
        if visibleSurfaces.insert(surface).inserted {
            reschedulePolling()
            rescheduleEventsPolling()
        }
        requestRefresh()
    }

    private func surfaceDidDisappear(_ surface: FleetSurface) {
        guard visibleSurfaces.remove(surface) != nil else { return }
        reschedulePolling()
        rescheduleEventsPolling()
    }

    private func requestRefresh() {
        Task { @MainActor [weak self] in await self?.refreshNow() }
    }

    private func requestEventsRefresh() {
        guard notificationCoverageMode == .allMajorChanges else { return }
        Task { @MainActor [weak self] in await self?.pollMajorEventsNow() }
    }

    private func scheduleNotifications(
        for snapshot: FleetSnapshot,
        isAuthoritativeComplete: Bool,
        revision: UInt64
    ) {
        _ = enqueueNotificationOperation { state, coordinator in
            guard state.notificationSnapshotRevision == revision,
                  state.notificationCoverageMode == .importantOnly else { return }
            let result = await coordinator.process(
                snapshot,
                isAuthoritativeComplete: isAuthoritativeComplete,
                shouldContinue: {
                    state.notificationSnapshotRevision == revision
                        && state.notificationCoverageMode == .importantOnly
                }
            )
            guard state.notificationSnapshotRevision == revision,
                  state.notificationCoverageMode == .importantOnly else { return }
            state.applyNotificationResult(result)
        }
    }

    @discardableResult
    private func enqueueNotificationOperation(
        _ operation: @escaping @MainActor (
            AppState,
            FleetNotificationCoordinator
        ) async -> Void
    ) -> Task<Void, Never>? {
        // Permission, reconciliation, and delivery share one ordered lane so an
        // older suspension cannot overwrite or notify after newer accepted state.
        guard let notificationCoordinator else { return nil }
        let precedingTask = notificationTask
        let task = Task { @MainActor [weak self] in
            await precedingTask?.value
            guard let self else { return }
            await operation(self, notificationCoordinator)
        }
        notificationTask = task
        return task
    }

    private func deliverLatestAcceptedSnapshotIfAuthorized(
        using notificationCoordinator: FleetNotificationCoordinator
    ) async {
        guard notificationCoverageMode == .importantOnly,
              notificationAuthorizationState == .authorized,
              let snapshot = lastAcceptedFreshSnapshotForNotifications else { return }
        let revision = notificationSnapshotRevision
        let result = await notificationCoordinator.process(
            snapshot,
            isAuthoritativeComplete: lastAcceptedFreshSnapshotIsAuthoritativeComplete,
            shouldContinue: {
                self.notificationSnapshotRevision == revision
                    && self.notificationCoverageMode == .importantOnly
            }
        )
        guard notificationSnapshotRevision == revision,
              notificationCoverageMode == .importantOnly else { return }
        applyNotificationResult(result)
    }

    private func applyNotificationResult(_ result: FleetNotificationResult) {
        notificationAuthorizationState = result.authorizationState
        notificationErrorMessage = result.deliveryErrors.isEmpty
            ? nil
            : "Some alerts could not be delivered and will be retried on the next fresh update."
    }

    private func performEventsRefresh(revision: UInt64) async {
        guard let eventsClient, let eventsCursorStore else { return }
        let storedCursor = eventsCursorStore.cursorSeq()
        if eventsSeedRequired || storedCursor == nil {
            await seedEventsFromTail(
                using: eventsClient,
                cursorStore: eventsCursorStore,
                revision: revision
            )
            return
        }
        guard let cursor = storedCursor else { return }

        do {
            let delivery = try await eventsClient.liveFleetEvents(since: cursor)
            guard eventsRevision == revision,
                  notificationCoverageMode == .allMajorChanges else { return }
            switch delivery {
            case let .events(envelope):
                let incrementalEvents = envelope.events.filter { $0.seq > cursor }
                if incrementalEvents.count > Self.maximumEventsPerPoll {
                    AppTelemetry.eventFeed(
                        message: "backlog of \(incrementalEvents.count) exceeded \(Self.maximumEventsPerPoll); reseeding"
                    )
                    eventsSeedRequired = true
                    await seedEventsFromTail(
                        using: eventsClient,
                        cursorStore: eventsCursorStore,
                        revision: revision
                    )
                    return
                }
                await processEventsEnvelope(
                    incrementalEvents,
                    envelopeCursorSeq: envelope.cursor.seq,
                    revision: revision
                )
            case let .error(envelope):
                switch envelope.error.code {
                case "cursor_expired", "invalid_cursor":
                    AppTelemetry.eventFeed(
                        message: "\(envelope.error.code); reseeding from tail"
                    )
                    eventsSeedRequired = true
                    await seedEventsFromTail(
                        using: eventsClient,
                        cursorStore: eventsCursorStore,
                        revision: revision
                    )
                default:
                    AppTelemetry.eventFeed(
                        message: "\(envelope.error.code): \(envelope.error.message); retrying after the current cadence"
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch let error as CrucibleCLIClientError {
            guard eventsRevision == revision,
                  notificationCoverageMode == .allMajorChanges else { return }
            if case let .outputTooLarge(limit) = error {
                AppTelemetry.eventFeed(
                    message: "incremental output exceeded \(limit) bytes; reseeding from tail"
                )
                eventsSeedRequired = true
                await seedEventsFromTail(
                    using: eventsClient,
                    cursorStore: eventsCursorStore,
                    revision: revision
                )
            } else {
                AppTelemetry.eventFeed(
                    message: "poll failed: \(error.localizedDescription); retrying after the current cadence"
                )
            }
        } catch {
            AppTelemetry.eventFeed(
                message: "poll failed: \(error.localizedDescription); retrying after the current cadence"
            )
        }
    }

    private func seedEventsFromTail(
        using eventsClient: any CrucibleCLIClient,
        cursorStore: EventsCursorStore,
        revision: UInt64
    ) async {
        do {
            let delivery = try await eventsClient.liveFleetEvents(since: nil)
            guard eventsRevision == revision,
                  notificationCoverageMode == .allMajorChanges else { return }
            switch delivery {
            case let .events(envelope):
                cursorStore.store(envelope.cursor.seq)
                eventsSeedRequired = false
                AppTelemetry.eventFeed(
                    message: "seeded at cursor \(envelope.cursor.seq); skipped \(envelope.events.count) historical events"
                )
            case let .error(envelope):
                AppTelemetry.eventFeed(
                    message: "seed failed with \(envelope.error.code): \(envelope.error.message)"
                )
            }
        } catch is CancellationError {
            return
        } catch let error as CrucibleCLIClientError {
            if case let .outputTooLarge(limit) = error {
                guard eventsRevision == revision,
                      notificationCoverageMode == .allMajorChanges else { return }
                eventsSeedRequired = true
                AppTelemetry.eventFeed(
                    message: "tail reseed output exceeded \(limit) bytes; keeping reseed pending"
                )
            } else {
                AppTelemetry.eventFeed(message: "seed failed: \(error.localizedDescription)")
            }
        } catch {
            AppTelemetry.eventFeed(message: "seed failed: \(error.localizedDescription)")
        }
    }

    private func processEventsEnvelope(
        _ events: [LiveFleetEventV1],
        envelopeCursorSeq: Int,
        revision: UInt64
    ) async {
        let task = enqueueNotificationOperation { state, coordinator in
            guard state.eventsRevision == revision,
                  state.notificationCoverageMode == .allMajorChanges else { return }
            let result = await coordinator.processEvents(
                events,
                shouldContinue: {
                    state.eventsRevision == revision
                        && state.notificationCoverageMode == .allMajorChanges
                }
            )
            guard state.eventsRevision == revision,
                  state.notificationCoverageMode == .allMajorChanges else { return }
            state.notificationAuthorizationState = result.authorizationState
            if !result.deliveryErrors.isEmpty {
                state.notificationErrorMessage = "Some fleet events could not be delivered and will retry from the durable event cursor."
            }
            if let newCursor = result.newCursor {
                state.eventsCursorStore?.advance(to: newCursor)
            }
            let fullyFinal = events.isEmpty
                || result.newCursor == events.last?.seq
            if fullyFinal {
                state.eventsCursorStore?.advance(to: envelopeCursorSeq)
            }
        }
        await task?.value
    }

    private func markEventsForReseedIfReauthorized(
        from priorAuthorization: NotificationAuthorizationState
    ) {
        guard notificationCoverageMode == .allMajorChanges,
              notificationAuthorizationState == .authorized,
              priorAuthorization != .authorized else { return }
        eventsRevision &+= 1
        eventsSeedRequired = true
        eventsRefreshTask?.cancel()
        eventsRefreshTask = nil
    }

    private func resolveNotificationTarget(_ route: FleetAlertRoute) {
        let exactSelection = FleetSelection.lane(jobID: route.jobID, laneID: route.laneID)
        guard snapshot?.job(id: route.jobID)?.hostID == route.hostID,
              snapshot?.detail(for: exactSelection) != nil else {
            selection = nil
            unresolvedNotificationTarget = UnresolvedNotificationTarget(
                route: route,
                reason: presentation.snapshotIsPartial ? .partialSnapshot : .targetUnavailable
            )
            return
        }
        unresolvedNotificationTarget = nil
        setSelection(exactSelection)
    }

    private func resolveActiveNotificationTargetIfNeeded() {
        guard let activeNotificationTargetRoute else { return }
        resolveNotificationTarget(activeNotificationTargetRoute)
    }

    private func reschedulePolling() {
        pollTask?.cancel()
        pollTask = nil
        guard pollingStarted else { return }
        let interval = pollInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self?.refreshNow()
            }
        }
    }

    private func rescheduleEventsPolling() {
        eventsPollTask?.cancel()
        eventsPollTask = nil
        guard pollingStarted,
              notificationCoverageMode == .allMajorChanges,
              eventsClient != nil,
              eventsCursorStore != nil,
              notificationCoordinator != nil else { return }
        let interval = pollInterval
        eventsPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self?.pollMajorEventsNow()
            }
        }
    }

}
