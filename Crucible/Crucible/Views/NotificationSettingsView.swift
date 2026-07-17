import SwiftUI

struct NotificationSettingsView: View {
    let state: AppState

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
                LabeledContent("Active alerts", value: "Important conditions")
                Text("Crucible alerts once per CLI condition episode for stalls and soft or hard time and token limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Additional alert coverage will appear only when the CLI can supply durable events that polling cannot miss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 330)
        .task {
            await state.refreshNotificationAuthorizationState()
        }
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
