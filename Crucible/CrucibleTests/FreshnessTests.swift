import Testing
@testable import Crucible

@MainActor
struct FreshnessTests {
    @Test("Preview and live states are current while error states are not")
    func freshnessSemantics() {
        let date = PreviewFixtures.sourceTimestamp

        #expect(FleetFreshness.preview(asOf: date).isCurrent)
        #expect(FleetFreshness.live(asOf: date).isCurrent)
        #expect(!FleetFreshness.stale(asOf: date).isCurrent)
        #expect(!FleetFreshness.incompatible.isCurrent)
        #expect(!FleetFreshness.unavailable.isCurrent)
    }

    @Test("Stale and failed presentations preserve last known state and useful errors")
    func errorStateRetention() {
        let stale = PreviewFixtures.stalePresentation
        let failed = PreviewFixtures.failedPresentation

        #expect(stale.snapshot == PreviewFixtures.fleet)
        #expect(stale.lastSuccessfulRefresh == PreviewFixtures.sourceTimestamp)
        #expect(stale.errorMessage?.contains("stale") == true)
        #expect(failed.snapshot == PreviewFixtures.fleet)
        #expect(failed.freshness == .unavailable)
        #expect(failed.errorMessage?.contains("failure") == true)
    }

    @Test("Production starts empty instead of falling back to fixtures")
    func productionUnavailable() {
        let presentation = FleetPresentation.productionUnavailable

        #expect(presentation.snapshot == nil)
        #expect(!presentation.isPreviewData)
        #expect(presentation.freshness == .unavailable)
        #expect(presentation.errorMessage != nil)
    }
}
