import Testing
@testable import Crucible

@MainActor
struct SelectionTests {
    @Test("State begins with the first host selected")
    func initialSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        #expect(state.selectedHostID == "forge-01")
        #expect(state.selectionDetail?.title == "forge-01")
        #expect(state.selectionDetail?.sourceTimestamp == PreviewFixtures.sourceTimestamp)
    }

    @Test("Job and lane selection derive progressive detail without AppKit")
    func progressiveSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectJob("CRU-142", on: "forge-01")
        #expect(state.selectionDetail?.title.contains("CRU-142") == true)
        #expect(state.selectionDetail?.currentStage == "Implement")

        state.selectLane("implement", in: "CRU-142", on: "forge-01")
        let detail = state.selectionDetail
        #expect(detail?.title == "Implementation")
        #expect(detail?.tokenUse == 31_880)
        #expect(detail?.tokenBounds == TokenBounds(soft: 100_000, hard: 150_000))
        #expect(detail?.timeBoundSeconds == 1_800)
        #expect(detail?.retryCount == 1)
    }

    @Test("Empty production state has no implicit preview selection")
    func unavailableSelection() {
        let state = AppState(initialPresentation: .productionUnavailable)

        #expect(state.snapshot == nil)
        #expect(state.selection == nil)
        #expect(state.selectionDetail == nil)
    }
}
