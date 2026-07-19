import Foundation

/// AC-6: the operator chooses between snapshot-backed important-condition
/// alerts and the CLI's comprehensive, durable event feed.
enum NotificationCoverageMode: String, CaseIterable, Identifiable, Sendable {
    case importantOnly = "important-only"
    case allMajorChanges = "all-major-changes"

    var id: Self { self }

    var title: String {
        switch self {
        case .importantOnly: "Important conditions"
        case .allMajorChanges: "All major changes"
        }
    }

    static let defaultsKey = "notification-coverage-mode"

    static func stored(in defaults: UserDefaults) -> NotificationCoverageMode {
        defaults.string(forKey: defaultsKey).flatMap(NotificationCoverageMode.init(rawValue:)) ?? .importantOnly
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
