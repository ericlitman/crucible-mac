import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var presentation: FleetPresentation
    private(set) var selection: FleetSelection?

    init(initialPresentation: FleetPresentation) {
        presentation = initialPresentation
        selection = initialPresentation.snapshot?.hosts.first.map { .host(hostID: $0.id) }
        AppTelemetry.launched(previewData: initialPresentation.isPreviewData)
    }

    var snapshot: FleetSnapshot? {
        presentation.snapshot
    }

    var selectedHostID: String? {
        selection?.hostID ?? snapshot?.hosts.first?.id
    }

    var selectedHost: HostSnapshot? {
        snapshot?.host(id: selectedHostID)
    }

    var selectionDetail: FleetSelectionDetail? {
        snapshot?.detail(for: selection)
    }

    func selectHost(_ hostID: String) {
        select(.host(hostID: hostID))
    }

    func selectJob(_ jobID: String, on hostID: String) {
        select(.job(hostID: hostID, jobID: jobID))
    }

    func selectLane(_ laneID: String, in jobID: String, on hostID: String) {
        select(.lane(hostID: hostID, jobID: jobID, laneID: laneID))
    }

    func select(_ newSelection: FleetSelection) {
        selection = newSelection
        switch newSelection {
        case let .host(hostID):
            AppTelemetry.selected(kind: "host", identifier: hostID)
        case let .job(_, jobID):
            AppTelemetry.selected(kind: "job", identifier: jobID)
        case let .lane(_, _, laneID):
            AppTelemetry.selected(kind: "lane", identifier: laneID)
        }
    }

    func menuBarDidAppear() {
        AppTelemetry.menuBarPresented()
    }

    func dashboardRequested() {
        AppTelemetry.dashboardRequested()
    }

    func dashboardDidAppear() {
        AppTelemetry.dashboardPresented()
    }
}
