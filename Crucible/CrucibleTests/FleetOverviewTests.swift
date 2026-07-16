import Testing
@testable import Crucible

@MainActor
struct FleetOverviewTests {
    @Test("Overview derives every named work-state count")
    func allNamedStateCounts() {
        let overview = FleetOverview(snapshot: PreviewFixtures.fleet)

        #expect(Set(overview.stateCounts.keys) == Set(WorkState.allCases))
        for state in WorkState.allCases {
            #expect(overview.count(for: state) == 1)
        }
    }

    @Test("Overview keeps every fixture host and queue item")
    func completeOverviewCollections() {
        let overview = FleetOverview(snapshot: PreviewFixtures.fleet)

        #expect(overview.hosts.map(\.id) == ["forge-01", "forge-02", "forge-03", "forge-04"])
        #expect(overview.queue.count == 6)
        #expect(overview.hosts.first?.capacityLabel == "7/10 lanes")
    }

    @Test("Work state labels remain explicit and non-color dependent")
    func workStateLabels() {
        #expect(WorkState.allCases.map(\.title) == [
            "Active", "Waiting", "Completed", "Failed", "Blocked", "Stalled",
        ])
        #expect(WorkState.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }
}
