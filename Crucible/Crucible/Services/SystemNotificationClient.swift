import Foundation
import UserNotifications

nonisolated enum NotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized

    var title: String {
        switch self {
        case .unknown: "Checking…"
        case .notDetermined: "Not enabled"
        case .denied: "Denied"
        case .authorized: "Authorized"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: "ellipsis.circle"
        case .notDetermined: "bell.badge"
        case .denied: "bell.slash.fill"
        case .authorized: "checkmark.circle.fill"
        }
    }
}

nonisolated protocol SystemNotificationClient: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> NotificationAuthorizationState
    func deliver(_ alert: FleetAlert) async throws
}

nonisolated final class UserNotificationClient: SystemNotificationClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationState() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        return Self.authorizationState(for: settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationState()
    }

    func deliver(_ alert: FleetAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = alert.subtitle
        content.body = alert.body
        content.sound = .default
        content.userInfo = [
            "condition_episode_id": alert.episodeID,
            "host_id": alert.hostID,
            "job_id": alert.jobID,
            "lane_id": alert.laneID,
        ]
        try await center.add(UNNotificationRequest(
            identifier: alert.episodeID,
            content: content,
            trigger: nil
        ))
    }

    private static func authorizationState(
        for status: UNAuthorizationStatus
    ) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unknown
        }
    }
}
