import Foundation

enum FleetFreshness: Equatable, Sendable {
    case preview(asOf: Date)
    case live(asOf: Date)
    /// A fresh snapshot with partial coverage: newer than anything displayed,
    /// but non-live and never presented as "Stale" or complete (AC-7).
    case incomplete(asOf: Date)
    case stale(asOf: Date)
    case incompatible
    case unavailable

    var title: String {
        switch self {
        case .preview: "Preview snapshot"
        case .live: "Live"
        case .incomplete: "Incomplete"
        case .stale: "Stale"
        case .incompatible: "Incompatible CLI"
        case .unavailable: "Unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .preview: "sparkles"
        case .live: "checkmark.circle.fill"
        case .incomplete: "circle.dashed"
        case .stale: "clock.badge.exclamationmark.fill"
        case .incompatible: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    var sourceDate: Date? {
        switch self {
        case let .preview(asOf), let .live(asOf), let .incomplete(asOf), let .stale(asOf): asOf
        case .incompatible, .unavailable: nil
        }
    }

    var isCurrent: Bool {
        switch self {
        case .preview, .live: true
        case .incomplete, .stale, .incompatible, .unavailable: false
        }
    }
}

struct FleetPresentation: Equatable, Sendable {
    let snapshot: FleetSnapshot?
    let freshness: FleetFreshness
    let lastSuccessfulRefresh: Date?
    let errorMessage: String?
    let isPreviewData: Bool

    static let productionUnavailable = FleetPresentation(
        snapshot: nil,
        freshness: .unavailable,
        lastSuccessfulRefresh: nil,
        errorMessage: "Waiting for the versioned Crucible CLI live-fleet response.",
        isPreviewData: false
    )
}
