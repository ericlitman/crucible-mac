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

nonisolated enum NotificationPresentationPolicy {
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]
}

nonisolated final class UserNotificationClient: SystemNotificationClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let delegate: CrucibleNotificationCenterDelegate

    init(center: UNUserNotificationCenter = .current()) {
        let delegate = CrucibleNotificationCenterDelegate()
        self.center = center
        self.delegate = delegate
        center.delegate = delegate
    }

    func setResponseHandler(
        _ handler: @escaping @MainActor @Sendable (FleetAlertRoute) -> Void
    ) {
        delegate.setResponseHandler(handler)
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
        content.userInfo = alert.route.userInfo
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

nonisolated final class CrucibleNotificationCenterDelegate: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    typealias ResponseHandler = @MainActor @Sendable (FleetAlertRoute) -> Void

    private let lock = NSLock()
    private var responseHandler: ResponseHandler?

    func setResponseHandler(_ handler: @escaping ResponseHandler) {
        lock.withLock { responseHandler = handler }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(NotificationPresentationPolicy.foregroundOptions)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = dispatchResponse(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    @discardableResult
    func dispatchResponse(userInfo: [AnyHashable: Any]) -> Task<Void, Never>? {
        let route = FleetAlertRoute(userInfo: userInfo)
        let handler = lock.withLock { responseHandler }
        guard let route, let handler else { return nil }
        return Task { @MainActor in handler(route) }
    }
}
