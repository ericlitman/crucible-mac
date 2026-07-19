import AppKit
import SwiftUI

@main
enum CrucibleApp {
    @MainActor
    static func main() {
        #if DEBUG
        switch PreviewHarness.proofSurface() {
        case .menu:
            PreviewMenuProofApp.main()
            return
        case .dashboard:
            PreviewDashboardProofApp.main()
            return
        case nil:
            break
        }
        #endif

        CrucibleRuntimeApp.main()
    }
}

private struct CrucibleRuntimeApp: App {
    @State private var state: AppState

    init() {
        let presentation = PreviewHarness.initialPresentation()
        let cliClient = ProcessCrucibleCLIClient()
        let coordinator = presentation.isPreviewData ? nil : FleetRefreshCoordinator(client: cliClient)
        let notificationClient = UserNotificationClient()
        let notificationCoordinator = FleetNotificationCoordinator(
            client: notificationClient,
            episodeStore: UserDefaultsNotificationEpisodeStore(),
            eventStore: FIFOEventDeliveryStore()
        )
        let appState = AppState(
            initialPresentation: presentation,
            refreshCoordinator: coordinator,
            notificationCoordinator: notificationCoordinator,
            eventsClient: presentation.isPreviewData ? nil : cliClient,
            eventsCursorStore: presentation.isPreviewData ? nil : EventsCursorStore(),
            automaticallyStarts: coordinator != nil
        )
        notificationClient.setResponseHandler { [weak appState] route in
            appState?.handleNotificationResponse(route)
        }
        _state = State(initialValue: appState)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(state: state)
        } label: {
            NotificationRoutingMenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("Crucible Fleet", id: "fleet-dashboard") {
            FleetDashboardView(state: state)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)

        Settings {
            NotificationSettingsView(state: state)
        }
    }
}

private struct NotificationRoutingMenuBarLabel: View {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel("Crucible")
            .onChange(of: state.notificationNavigationRequest?.id) { _, requestID in
                guard requestID != nil else { return }
                openWindow(id: "fleet-dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

#if DEBUG
private struct PreviewMenuProofApp: App {
    @State private var state: AppState
    private let colorScheme: ColorScheme?

    init() {
        let arguments = ProcessInfo.processInfo.arguments + [PreviewHarness.previewArgument]
        _state = State(initialValue: AppState(
            initialPresentation: PreviewHarness.initialPresentation(arguments: arguments)
        ))
        colorScheme = PreviewHarness.proofAppearance()?.colorScheme
    }

    var body: some Scene {
        WindowGroup("Crucible Preview Proof") {
            MenuBarContentView(state: state)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 390, height: 720)
        .windowResizability(.contentMinSize)
    }
}

private struct PreviewDashboardProofApp: App {
    @State private var state: AppState
    private let colorScheme: ColorScheme?

    init() {
        let arguments = ProcessInfo.processInfo.arguments + [PreviewHarness.previewArgument]
        _state = State(initialValue: AppState(
            initialPresentation: PreviewHarness.initialPresentation(arguments: arguments)
        ))
        colorScheme = PreviewHarness.proofAppearance()?.colorScheme
    }

    var body: some Scene {
        WindowGroup("Crucible Preview Proof") {
            FleetDashboardView(state: state)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
    }
}

private extension PreviewHarness.ProofAppearance {
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
