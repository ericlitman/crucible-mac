import Foundation
import OSLog

enum AppTelemetry {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mobilyze.Crucible"
    private static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    private static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    private static let dashboard = Logger(subsystem: subsystem, category: "Dashboard")

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
}
