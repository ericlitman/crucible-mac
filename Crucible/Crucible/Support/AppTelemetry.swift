import Foundation
import OSLog

enum AppTelemetry {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mobilyze.Crucible"
    private static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    private static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    private static let dashboard = Logger(subsystem: subsystem, category: "Dashboard")
    private static let notifications = Logger(subsystem: subsystem, category: "Notifications")

    static func launched(previewData: Bool) {
        lifecycle.info("App launched; previewData=\(previewData, privacy: .public)")
    }

    static func menuBarPresented() {
        menuBar.info("Menu bar surface presented")
    }

    static func dashboardRequested() {
        menuBar.info("Dashboard requested")
    }

    static func dashboardPresented() {
        dashboard.info("Dashboard window presented")
    }

    static func selected(kind: String, identifier: String) {
        dashboard.info("Selected \(kind, privacy: .public): \(identifier, privacy: .public)")
    }

    static func evaluatedNotifications(authorization: String, candidates: Int) {
        notifications.info(
            "Evaluated important conditions; authorization=\(authorization, privacy: .public), candidates=\(candidates, privacy: .public)"
        )
    }

    static func completedNotificationDelivery(delivered: Int, errors: Int) {
        notifications.info(
            "Completed important-condition delivery; delivered=\(delivered, privacy: .public), errors=\(errors, privacy: .public)"
        )
    }

    static func evaluatedEventNotifications(authorization: String, candidates: Int) {
        notifications.info(
            "Evaluated major fleet events; authorization=\(authorization, privacy: .public), candidates=\(candidates, privacy: .public)"
        )
    }

    static func completedEventNotificationDelivery(delivered: Int, errors: Int) {
        notifications.info(
            "Completed major-event delivery; delivered=\(delivered, privacy: .public), errors=\(errors, privacy: .public)"
        )
    }

    static func eventFeed(message: String) {
        notifications.notice("Live-fleet event feed: \(message, privacy: .public)")
    }
}
