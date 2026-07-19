import Foundation

/// AC-6: the operator chooses between important-condition alerts only and
/// alerts for all major state changes. All-major delivery additionally
/// consumes the CLI's durable, replayable event feed from a persisted cursor.
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
