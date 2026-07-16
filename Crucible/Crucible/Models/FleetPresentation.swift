import Foundation

enum FleetFreshness: Equatable, Sendable {
    case preview(asOf: Date)
    case live(asOf: Date)
    case stale(asOf: Date)
    case incompatible
    case unavailable

    var title: String {
        switch self {
        case .preview: "Preview snapshot"
        case .live: "Live"
        case .stale: "Stale"
        case .incompatible: "Incompatible CLI"
        case .unavailable: "Unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .preview: "sparkles"
        case .live: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark.fill"
        case .incompatible: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    var sourceDate: Date? {
        switch self {
        case let .preview(asOf), let .live(asOf), let .stale(asOf): asOf
        case .incompatible, .unavailable: nil
        }
    }

    var isCurrent: Bool {
        switch self {
        case .preview, .live: true
        case .stale, .incompatible, .unavailable: false
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
        errorMessage: "Live fleet data is not connected yet. A versioned Crucible CLI adapter will supply it in a later slice.",
        isPreviewData: false
    )
}

/// The only data-source seam in this foundation. CRUMAC-6 intentionally ships
/// no production implementation and never invokes it.
protocol FleetSnapshotProviding: Sendable {
    func snapshot() async throws -> FleetSnapshot
}
