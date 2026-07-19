import SwiftUI

struct NotificationSettingsView: View {
    let state: AppState
    @Environment(\.scenePhase) private var scenePhase

    private let systemNotificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )!

    var body: some View {
        Form {
            Section("Delivery") {
                LabeledContent("Permission") {
                    Label(
                        state.notificationAuthorizationState.title,
                        systemImage: state.notificationAuthorizationState.symbolName
                    )
                    .foregroundStyle(permissionTint)
                }

                Text(permissionExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.notificationAuthorizationState == .notDetermined {
                    Button("Enable Notifications") {
                        Task { await state.requestNotificationAuthorization() }
                    }
                } else if state.notificationAuthorizationState == .denied {
                    Link("Open Notification Settings", destination: systemNotificationSettingsURL)
                }

                if let errorMessage = state.notificationErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Coverage") {
                Picker("Alert coverage", selection: coverageModeBinding) {
                    ForEach(NotificationCoverageMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                switch state.notificationCoverageMode {
                case .importantOnly:
                    Text("Stall and soft or hard time-limit protection is active. Crucible alerts once per CLI condition episode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .allMajorChanges:
                    Label(
                        "Major fleet changes are delivered from the Crucible CLI event feed. Delivery starts from now, advances a durable cursor, and deduplicates replayed events; important conditions continue to alert.",
                        systemImage: "bell.badge.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                LabeledContent("Token-limit alerts", value: "Waiting for CLI telemetry")
                Text("Token-limit protection is unavailable until the Crucible CLI supplies authoritative token usage and boundary conditions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Major changes come from the ordered CLI event feed; Crucible does not infer transitions by comparing snapshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .task {
            await state.notificationSettingsDidBecomeActive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await state.notificationSettingsDidBecomeActive() }
        }
    }

    private var coverageModeBinding: Binding<NotificationCoverageMode> {
        Binding(
            get: { state.notificationCoverageMode },
            set: { state.setNotificationCoverageMode($0) }
        )
    }

    private var permissionTint: Color {
        switch state.notificationAuthorizationState {
        case .authorized: .green
        case .denied: .red
        case .notDetermined: .orange
        case .unknown: .secondary
        }
    }

    private var permissionExplanation: String {
        switch state.notificationAuthorizationState {
        case .unknown:
            "Checking the current macOS notification permission."
        case .notDetermined:
            "Crucible will ask only when you choose Enable Notifications."
        case .denied:
            "macOS is blocking Crucible alerts. You can allow them in System Settings."
        case .authorized:
            "macOS can deliver Crucible alerts, including while the app is in the background."
        }
    }
}
