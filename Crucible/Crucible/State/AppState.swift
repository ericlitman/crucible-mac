import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var presentation: FleetPresentation
    private(set) var selection: FleetSelection?
    private(set) var isRefreshing = false
    private(set) var visibleSurfaces: Set<FleetSurface> = []
    private(set) var notificationAuthorizationState: NotificationAuthorizationState = .unknown
    private(set) var notificationErrorMessage: String?
    private(set) var unresolvedNotificationTarget: UnresolvedNotificationTarget?
    private(set) var notificationNavigationRequest: NotificationNavigationRequest?

    private let refreshCoordinator: FleetRefreshCoordinator?
    private let notificationCoordinator: FleetNotificationCoordinator?
    private var presentationReducer: FleetPresentationReducer
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var pollingStarted = false
    private var lastAcceptedFreshSnapshotForNotifications: FleetSnapshot?
    private var lastAcceptedFreshSnapshotIsAuthoritativeComplete = false
    private var currentSnapshotIsPartial = false
    private var activeNotificationTargetRoute: FleetAlertRoute?

    init(
        initialPresentation: FleetPresentation,
        refreshCoordinator: FleetRefreshCoordinator? = nil,
        notificationCoordinator: FleetNotificationCoordinator? = nil,
        automaticallyStarts: Bool = false
    ) {
        presentation = initialPresentation
        presentationReducer = FleetPresentationReducer(initialPresentation: initialPresentation)
        self.refreshCoordinator = refreshCoordinator
        self.notificationCoordinator = notificationCoordinator
        selection = initialPresentation.snapshot?.hosts.first.map { .host(hostID: $0.id) }
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
        guard let selection else { return snapshot?.hosts.first?.id }
        switch selection {
        case let .host(hostID): return hostID
        case let .job(jobID), let .lane(jobID, _): return snapshot?.job(id: jobID)?.hostID
        }
    }

    var selectedHost: HostSnapshot? { snapshot?.host(id: selectedHostID) }

    var selectionDetail: FleetSelectionDetail? { snapshot?.detail(for: selection) }

    var pollInterval: TimeInterval {
        FleetRefreshCadence.interval(hasVisibleSurface: !visibleSurfaces.isEmpty)
    }

    func startPolling() {
        guard !pollingStarted, refreshCoordinator != nil else { return }
        pollingStarted = true
        reschedulePolling()
        requestRefresh()
    }

    func stopPolling() {
        pollingStarted = false
        pollTask?.cancel()
        pollTask = nil
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
                reconcileSelection()
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
        if let isPartial = reduction.acceptedFreshSnapshotIsPartial {
            currentSnapshotIsPartial = isPartial
        }
        resolveActiveNotificationTargetIfNeeded()
        reconcileSelection()
        if let snapshot = reduction.acceptedFreshSnapshot {
            lastAcceptedFreshSnapshotForNotifications = snapshot
            let isAuthoritativeComplete = reduction.acceptedFreshSnapshotIsPartial == false
            lastAcceptedFreshSnapshotIsAuthoritativeComplete = isAuthoritativeComplete
            scheduleNotifications(
                for: snapshot,
                isAuthoritativeComplete: isAuthoritativeComplete
            )
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
            state.notificationAuthorizationState = await coordinator.authorizationState()
            await state.deliverLatestAcceptedSnapshotIfAuthorized(using: coordinator)
        }
        await task?.value
    }

    func requestNotificationAuthorization() async {
        let task = enqueueNotificationOperation { state, coordinator in
            state.notificationErrorMessage = nil
            do {
                state.notificationAuthorizationState = try await coordinator.requestAuthorization()
                await state.deliverLatestAcceptedSnapshotIfAuthorized(using: coordinator)
            } catch {
                state.notificationErrorMessage = "Notification permission could not be updated: \(error.localizedDescription)"
                state.notificationAuthorizationState = await coordinator.authorizationState()
            }
        }
        await task?.value
    }

    func waitForNotificationEvaluation() async {
        await notificationTask?.value
    }

    func handleNotificationResponse(_ route: FleetAlertRoute) {
        notificationNavigationRequest = NotificationNavigationRequest(route: route)
        activeNotificationTargetRoute = route
        resolveNotificationTarget(route)
    }

    private func surfaceDidAppear(_ surface: FleetSurface) {
        if visibleSurfaces.insert(surface).inserted {
            reschedulePolling()
        }
        requestRefresh()
    }

    private func surfaceDidDisappear(_ surface: FleetSurface) {
        guard visibleSurfaces.remove(surface) != nil else { return }
        reschedulePolling()
    }

    private func requestRefresh() {
        Task { @MainActor [weak self] in await self?.refreshNow() }
    }

    private func scheduleNotifications(
        for snapshot: FleetSnapshot,
        isAuthoritativeComplete: Bool
    ) {
        _ = enqueueNotificationOperation { state, coordinator in
            state.applyNotificationResult(await coordinator.process(
                snapshot,
                isAuthoritativeComplete: isAuthoritativeComplete
            ))
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
        guard notificationAuthorizationState == .authorized,
              let snapshot = lastAcceptedFreshSnapshotForNotifications else { return }
        applyNotificationResult(await notificationCoordinator.process(
            snapshot,
            isAuthoritativeComplete: lastAcceptedFreshSnapshotIsAuthoritativeComplete
        ))
    }

    private func applyNotificationResult(_ result: FleetNotificationResult) {
        notificationAuthorizationState = result.authorizationState
        notificationErrorMessage = result.deliveryErrors.isEmpty
            ? nil
            : "Some alerts could not be delivered and will be retried on the next fresh update."
    }

    private func resolveNotificationTarget(_ route: FleetAlertRoute) {
        let exactSelection = FleetSelection.lane(jobID: route.jobID, laneID: route.laneID)
        guard snapshot?.job(id: route.jobID)?.hostID == route.hostID,
              snapshot?.detail(for: exactSelection) != nil else {
            selection = nil
            unresolvedNotificationTarget = UnresolvedNotificationTarget(
                route: route,
                reason: currentSnapshotIsPartial ? .partialSnapshot : .targetUnavailable
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

    private func reconcileSelection() {
        guard unresolvedNotificationTarget == nil else { return }
        if let selection, snapshot?.detail(for: selection) != nil { return }
        selection = snapshot?.hosts.first.map { .host(hostID: $0.id) }
    }

}
