import Foundation

struct FleetPresentationReduction {
    let presentation: FleetPresentation
    let acceptedFreshSnapshot: FleetSnapshot?
    let acceptedFreshSnapshotIsPartial: Bool?
}

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
    ) -> FleetPresentationReduction {
        switch delivery {
        case let .snapshot(contract): reduce(contract, current: current)
        case let .error(envelope): FleetPresentationReduction(
            presentation: reduce(envelope, current: current),
            acceptedFreshSnapshot: nil,
            acceptedFreshSnapshotIsPartial: nil
        )
        }
    }

    func reducingFailure(_ error: Error, current: FleetPresentation) -> FleetPresentation {
        let retained = current.snapshot ?? lastCompleteSnapshot
        return FleetPresentation(
            snapshot: retained,
            freshness: retained.map { .stale(asOf: $0.sourceTimestamp) } ?? .unavailable,
            lastSuccessfulRefresh: current.lastSuccessfulRefresh,
            errorMessage: error.localizedDescription,
            isPreviewData: false,
            snapshotIsPartial: retained != nil && current.snapshot != nil && current.snapshotIsPartial
        )
    }

    private mutating func reduce(
        _ contract: LiveFleetSnapshotV1,
        current: FleetPresentation
    ) -> FleetPresentationReduction {
        let incoming = contract.presentationSnapshot()
        let prior = current.snapshot ?? lastCompleteSnapshot

        if let prior, prior.sourceTimestamp > incoming.sourceTimestamp {
            return FleetPresentationReduction(
                presentation: current,
                acceptedFreshSnapshot: nil,
                acceptedFreshSnapshotIsPartial: nil
            )
        }

        if contract.freshness.state == .fresh, contract.completeness.state == .complete {
            lastCompleteSnapshot = incoming
            return FleetPresentationReduction(
                presentation: FleetPresentation(
                    snapshot: incoming,
                    freshness: .live(asOf: incoming.sourceTimestamp),
                    lastSuccessfulRefresh: contract.generatedAt,
                    errorMessage: nil,
                    isPreviewData: false,
                    snapshotIsPartial: false
                ),
                acceptedFreshSnapshot: incoming,
                acceptedFreshSnapshotIsPartial: false
            )
        }

        if contract.freshness.state == .stale {
            let retained = current.snapshot ?? lastCompleteSnapshot ?? incoming
            // Track the displayed snapshot's completeness: the retained current
            // presentation keeps its flag, a retained last-complete snapshot is
            // complete, and a displayed stale incoming derives from the contract.
            let retainedIsPartial: Bool
            if current.snapshot != nil {
                retainedIsPartial = current.snapshotIsPartial
            } else if lastCompleteSnapshot != nil {
                retainedIsPartial = false
            } else {
                retainedIsPartial = contract.completeness.state != .complete
            }
            return FleetPresentationReduction(
                presentation: FleetPresentation(
                    snapshot: retained,
                    freshness: .stale(asOf: retained.sourceTimestamp),
                    lastSuccessfulRefresh: current.lastSuccessfulRefresh,
                    errorMessage: staleMessage(contract),
                    isPreviewData: false,
                    snapshotIsPartial: retainedIsPartial
                ),
                acceptedFreshSnapshot: nil,
                acceptedFreshSnapshotIsPartial: nil
            )
        }

        return FleetPresentationReduction(
            presentation: FleetPresentation(
                snapshot: incoming,
                freshness: .incomplete(asOf: incoming.sourceTimestamp),
                lastSuccessfulRefresh: current.lastSuccessfulRefresh,
                errorMessage: incompleteMessage(contract.completeness.reasons),
                isPreviewData: false,
                snapshotIsPartial: true
            ),
            acceptedFreshSnapshot: incoming,
            acceptedFreshSnapshotIsPartial: true
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
            isPreviewData: false,
            snapshotIsPartial: retained != nil && current.snapshot != nil && current.snapshotIsPartial
        )
    }

    private func staleMessage(_ contract: LiveFleetSnapshotV1) -> String {
        let age = contract.freshness.ageSeconds.map { FleetFormat.duration($0) } ?? "an unknown duration"
        let reasons = contract.completeness.reasons.isEmpty
            ? "source age exceeded its bound"
            : contract.completeness.reasons.joined(separator: ", ")
        return "CLI data is stale by \(age) (\(reasons))."
    }

    private func incompleteMessage(_ reasons: [String]) -> String {
        let detail = reasons.isEmpty ? "the CLI reported partial coverage" : reasons.joined(separator: ", ")
        return "CLI refresh is incomplete; showing the newest available partial snapshot (\(detail))."
    }
}
