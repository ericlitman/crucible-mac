import Testing
@testable import Crucible

@MainActor
struct SelectionTests {
    @Test("State begins in the queue scope with no implicit selection")
    func initialSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        #expect(state.selection == nil)
        #expect(state.selectedHostID == nil)
        #expect(state.selectionDetail == nil)
        #expect(state.unresolvedSelection == nil)
    }

    @Test("A selection absent from the snapshot is retained with identity and reason")
    func retainedUnresolvedSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectJob("CRU-999")

        #expect(state.selection == .job(jobID: "CRU-999"))
        #expect(state.selectionDetail == nil)
        let unresolved = state.unresolvedSelection
        #expect(unresolved?.identityLabel == "CRU-999")
        #expect(unresolved?.kindLabel == "job")
        #expect(unresolved?.explanation.contains("not present in the current snapshot") == true)
    }

    @Test("Snapshot updates never silently replace an unresolvable selection")
    func snapshotUpdateRetainsSelection() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(incomplete) = try LiveFleetFixture.incomplete.delivery else { return }
        state.apply(.snapshot(incomplete))
        state.selectHost("studio1")
        #expect(state.selectedHost != nil)

        // A later failure retains the snapshot; the selection must survive too.
        state.apply(try LiveFleetFixture.failed.delivery)

        #expect(state.selection == .host(hostID: "studio1"))
    }

    @Test("The Queue scope is reachable again after any entity selection")
    func queueScopeRoundTrip() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectHost("forge-01")
        #expect(state.selectedHost != nil)

        state.selectQueue()
        #expect(state.selection == nil)
        #expect(state.selectedHostID == nil)
        #expect(state.unresolvedSelection == nil)

        state.selectJob("CRU-999")
        #expect(state.unresolvedSelection != nil)
        state.selectQueue()
        #expect(state.unresolvedSelection == nil)
    }

    @Test("A host-less job selection exposes its job context for the content column")
    func hostlessJobContext() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectJob("CRU-143")

        #expect(state.selectedHost == nil)
        #expect(state.selectedHostlessJob?.id == "CRU-143")

        state.selectHost("forge-01")
        #expect(state.selectedHostlessJob == nil)
    }

    @Test("Job and lane selection derive progressive detail without AppKit")
    func progressiveSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectJob("CRU-142")
        #expect(state.selectionDetail?.title.contains("CRU-142") == true)
        #expect(state.selectionDetail?.currentStage == "Implement")

        state.selectLane("implement", in: "CRU-142")
        let detail = state.selectionDetail
        #expect(detail?.title == "Implementation")
        #expect(detail?.tokenUse == 31_880)
        #expect(detail?.tokenBounds == TokenBounds(soft: 100_000, hard: 150_000))
        #expect(detail?.timeBounds == TimeBounds(softSeconds: nil, hardSeconds: 1_800))
        #expect(detail?.retryCount == 1)
    }

    @Test("Unassigned preview queue work is selectable without a synthetic host")
    func hostlessPreviewSelection() {
        let state = AppState(initialPresentation: PreviewFixtures.healthyPresentation)

        state.selectJob("CRU-143")

        #expect(state.selectedHostID == nil)
        #expect(state.selectedHost == nil)
        #expect(state.selectionDetail?.eyebrow == "Job • Unassigned queue")
        #expect(state.selectionDetail?.title.contains("CRU-143") == true)
    }

    @Test("Empty production state has no implicit preview selection")
    func unavailableSelection() {
        let state = AppState(initialPresentation: .productionUnavailable)

        #expect(state.snapshot == nil)
        #expect(state.selection == nil)
        #expect(state.selectionDetail == nil)
    }
}
