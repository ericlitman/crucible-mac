import Foundation
import Testing
@testable import Crucible

@MainActor
struct FreshnessTests {
    @Test("Preview and live states are current while error states are not")
    func freshnessSemantics() {
        let date = PreviewFixtures.sourceTimestamp

        #expect(FleetFreshness.preview(asOf: date).isCurrent)
        #expect(FleetFreshness.live(asOf: date).isCurrent)
        #expect(!FleetFreshness.incomplete(asOf: date).isCurrent)
        #expect(!FleetFreshness.stale(asOf: date).isCurrent)
        #expect(!FleetFreshness.incompatible.isCurrent)
        #expect(!FleetFreshness.unavailable.isCurrent)
    }

    @Test("Incomplete labeling is distinct from staleness and preserves the source date")
    func incompleteSemantics() {
        let date = PreviewFixtures.sourceTimestamp
        let incomplete = FleetFreshness.incomplete(asOf: date)

        #expect(incomplete.title == "Incomplete")
        #expect(incomplete.title != FleetFreshness.stale(asOf: date).title)
        #expect(incomplete.symbolName != FleetFreshness.stale(asOf: date).symbolName)
        #expect(incomplete.sourceDate == date)
        #expect(incomplete != .stale(asOf: date))
    }

    @Test("Stale and failed presentations preserve last known state and useful errors")
    func errorStateRetention() {
        let stale = PreviewFixtures.stalePresentation
        let failed = PreviewFixtures.failedPresentation

        #expect(stale.snapshot == PreviewFixtures.fleet)
        #expect(stale.lastSuccessfulRefresh == PreviewFixtures.sourceTimestamp)
        #expect(stale.errorMessage?.contains("stale") == true)
        #expect(failed.snapshot == PreviewFixtures.fleet)
        #expect(failed.freshness == .stale(asOf: PreviewFixtures.sourceTimestamp))
        #expect(failed.errorMessage?.contains("failure") == true)
    }

    @Test("Condition measures format with their CLI-type units")
    func conditionMeasureUnits() {
        func condition(type: String, actual: Double, bound: Double) -> FleetConditionSnapshot {
            FleetConditionSnapshot(
                id: "c-\(type)", type: type, severity: .warning,
                hostID: nil, jobID: nil, laneID: nil,
                firstObservedAt: .now, lastObservedAt: .now,
                actual: actual, bound: bound, action: nil
            )
        }

        let time = condition(type: "time_soft_bound_exceeded", actual: 2082, bound: 1260)
        #expect(time.formattedMeasure(2082) == "34m")
        #expect(time.formattedMeasure(1260) == "21m")

        let stall = condition(type: "no_progress_stall", actual: 720, bound: 600)
        #expect(stall.formattedMeasure(720) == "12m")

        let tokens = condition(type: "token_soft_bound_exceeded", actual: 2100, bound: 1000)
        #expect(tokens.formattedMeasure(2100) == "2.1K tokens")

        let unknown = condition(type: "mystery_condition", actual: 5, bound: 4)
        #expect(unknown.formattedMeasure(5) == "5")
    }

    @Test("Threshold conditions never present as failure-grade red")
    func conditionPresentationClasses() {
        func condition(type: String, severity: FleetConditionSeverity) -> FleetConditionSnapshot {
            FleetConditionSnapshot(
                id: "c-\(type)", type: type, severity: severity,
                hostID: nil, jobID: nil, laneID: nil,
                firstObservedAt: .now, lastObservedAt: .now,
                actual: 10, bound: 5, action: nil
            )
        }

        #expect(condition(type: "stalled", severity: .error).presentationClass == .noRecentProgress)
        #expect(condition(type: "no_progress_stall", severity: .error).presentationClass == .noRecentProgress)
        #expect(condition(type: "time_soft_bound_exceeded", severity: .warning).presentationClass == .overTime)
        #expect(condition(type: "time_hard_bound_exceeded", severity: .error).presentationClass == .overTime)
        #expect(condition(type: "token_soft_bound_exceeded", severity: .warning).presentationClass == .overTokens)
        #expect(condition(type: "provider_auth_failed", severity: .error).presentationClass == .failure)
        #expect(condition(type: "source_stale", severity: .warning).presentationClass == .advisory)
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
