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
        let coordinator = presentation.isPreviewData ? nil : FleetRefreshCoordinator(client: ProcessCrucibleCLIClient())
        let notificationCoordinator = FleetNotificationCoordinator(
            client: UserNotificationClient(),
            episodeStore: UserDefaultsNotificationEpisodeStore()
        )
        _state = State(initialValue: AppState(
            initialPresentation: presentation,
            refreshCoordinator: coordinator,
            notificationCoordinator: notificationCoordinator,
            automaticallyStarts: coordinator != nil
        ))
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

        Settings {
            NotificationSettingsView(state: state)
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
