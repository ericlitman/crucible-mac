import Foundation

enum FleetSurface: Hashable, Sendable {
    case menuBar
    case dashboard
}

enum FleetRefreshCadence {
    static let foreground: TimeInterval = 60
    static let background: TimeInterval = 300

    static func interval(hasVisibleSurface: Bool) -> TimeInterval {
        hasVisibleSurface ? foreground : background
    }
}
