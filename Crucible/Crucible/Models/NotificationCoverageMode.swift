import Foundation

/// AC-6: the operator chooses between important-condition alerts only and
/// alerts for all major state changes. All-major delivery additionally
/// requires the CLI's durable, replayable event feed; until that ships, the
/// choice is persisted and presented truthfully as pending.
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
