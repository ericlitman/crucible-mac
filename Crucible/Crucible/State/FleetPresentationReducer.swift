import Foundation

@MainActor
struct FleetPresentationReducer {
    private var lastCompleteSnapshot: FleetSnapshot?

    init(initialPresentation: FleetPresentation) {
        if initialPresentation.snapshot != nil,
           initialPresentation.freshness.isCurrent,
           initialPresentation.errorMessage == nil {
            lastCompleteSnapshot = initialPresentation.snapshot
        }
    }

    mutating func reduce(
        _ delivery: LiveFleetDelivery,
        current: FleetPresentation
    ) -> FleetPresentation {
        switch delivery {
        case let .snapshot(contract): reduce(contract, current: current)
        case let .error(envelope): reduce(envelope, current: current)
        }
    }

    func reducingFailure(_ error: Error, current: FleetPresentation) -> FleetPresentation {
        let retained = current.snapshot ?? lastCompleteSnapshot
        return FleetPresentation(
            snapshot: retained,
            freshness: retained.map { .stale(asOf: $0.sourceTimestamp) } ?? .unavailable,
            lastSuccessfulRefresh: current.lastSuccessfulRefresh,
            errorMessage: error.localizedDescription,
            isPreviewData: false
        )
    }

    private mutating func reduce(
        _ contract: LiveFleetSnapshotV1,
        current: FleetPresentation
    ) -> FleetPresentation {
        let incoming = contract.presentationSnapshot()

        if contract.freshness.state == .fresh, contract.completeness.state == .complete {
            lastCompleteSnapshot = incoming
            return FleetPresentation(
                snapshot: incoming,
                freshness: .live(asOf: incoming.sourceTimestamp),
                lastSuccessfulRefresh: contract.generatedAt,
                errorMessage: nil,
                isPreviewData: false
            )
        }

        if contract.freshness.state == .stale {
            let retained = current.snapshot ?? lastCompleteSnapshot ?? incoming
            return FleetPresentation(
                snapshot: retained,
                freshness: .stale(asOf: retained.sourceTimestamp),
                lastSuccessfulRefresh: current.lastSuccessfulRefresh,
                errorMessage: staleMessage(contract),
                isPreviewData: false
            )
        }

        let prior = current.snapshot ?? lastCompleteSnapshot
        let retained = prior ?? incoming
        return FleetPresentation(
            snapshot: retained,
            freshness: .stale(asOf: retained.sourceTimestamp),
            lastSuccessfulRefresh: current.lastSuccessfulRefresh,
            errorMessage: incompleteMessage(contract.completeness.reasons, retainedPrior: prior != nil),
            isPreviewData: false
        )
    }

    private func reduce(
        _ envelope: LiveFleetErrorEnvelopeV1,
        current: FleetPresentation
    ) -> FleetPresentation {
        let retained = current.snapshot ?? lastCompleteSnapshot
        let freshness: FleetFreshness
        if let retained {
            freshness = .stale(asOf: retained.sourceTimestamp)
        } else if envelope.error.kind == .incompatible {
            freshness = .incompatible
        } else {
            freshness = .unavailable
        }
        return FleetPresentation(
            snapshot: retained,
            freshness: freshness,
            lastSuccessfulRefresh: current.lastSuccessfulRefresh,
            errorMessage: envelope.error.message,
            isPreviewData: false
        )
    }

    private func staleMessage(_ contract: LiveFleetSnapshotV1) -> String {
        let age = contract.freshness.ageSeconds.map { FleetFormat.duration($0) } ?? "an unknown duration"
        let reasons = contract.completeness.reasons.isEmpty
            ? "source age exceeded its bound"
            : contract.completeness.reasons.joined(separator: ", ")
        return "CLI data is stale by \(age) (\(reasons))."
    }

    private func incompleteMessage(_ reasons: [String], retainedPrior: Bool) -> String {
        let detail = reasons.isEmpty ? "the CLI reported partial coverage" : reasons.joined(separator: ", ")
        let action = retainedPrior
            ? "preserving the last known snapshot"
            : "showing the available partial snapshot"
        return "CLI refresh is incomplete; \(action) (\(detail))."
    }
}
