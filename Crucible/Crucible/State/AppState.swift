import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var presentation: FleetPresentation
    private(set) var selection: FleetSelection?
    private(set) var isRefreshing = false
    private(set) var visibleSurfaces: Set<FleetSurface> = []

    private let refreshCoordinator: FleetRefreshCoordinator?
    private var presentationReducer: FleetPresentationReducer
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var pollingStarted = false

    init(
        initialPresentation: FleetPresentation,
        refreshCoordinator: FleetRefreshCoordinator? = nil,
        automaticallyStarts: Bool = false
    ) {
        presentation = initialPresentation
        presentationReducer = FleetPresentationReducer(initialPresentation: initialPresentation)
        self.refreshCoordinator = refreshCoordinator
        selection = initialPresentation.snapshot?.hosts.first.map { .host(hostID: $0.id) }
        AppTelemetry.launched(previewData: initialPresentation.isPreviewData)

        if automaticallyStarts {
            Task { @MainActor [weak self] in self?.startPolling() }
        }
    }

    var snapshot: FleetSnapshot? { presentation.snapshot }

    var selectedHostID: String? {
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
        presentation = presentationReducer.reduce(delivery, current: presentation)
        reconcileSelection()
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
        if let selection, snapshot?.detail(for: selection) != nil { return }
        selection = snapshot?.hosts.first.map { .host(hostID: $0.id) }
    }

}
