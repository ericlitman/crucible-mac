import SwiftUI

@main
struct CrucibleApp: App {
    @State private var state: AppState

    init() {
        let presentation = PreviewHarness.initialPresentation()
        _state = State(initialValue: AppState(initialPresentation: presentation))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(state: state)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Crucible")
        }
        .menuBarExtraStyle(.window)

        Window("Crucible Fleet", id: "fleet-dashboard") {
            FleetDashboardView(state: state)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
    }
}
