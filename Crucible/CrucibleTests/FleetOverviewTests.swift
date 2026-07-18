import Testing
@testable import Crucible

@MainActor
struct FleetOverviewTests {
    @Test("Overview derives every named work-state count")
    func allNamedStateCounts() {
        let overview = FleetOverview(snapshot: PreviewFixtures.fleet)

        #expect(Set(overview.stateCounts.keys) == Set(WorkState.allCases))
        for state in WorkState.allCases where state != .unknown {
            #expect(overview.count(for: state) == 1)
        }
        #expect(overview.count(for: .unknown) == 0)
    }

    @Test("Overview keeps every fixture host and queue item")
    func completeOverviewCollections() {
        let overview = FleetOverview(snapshot: PreviewFixtures.fleet)

        #expect(overview.hosts.map(\.id) == ["forge-01", "forge-02", "forge-03", "forge-04"])
        #expect(overview.queue.count == 6)
        #expect(overview.hosts.first?.capacityLabel == "7/10 lanes")
    }

    @Test("Per-host job truncation survives parsing and is exposed, never a confident empty host")
    func hostJobTruncationExposed() throws {
        guard case let .snapshot(incomplete) = try LiveFleetFixture.incomplete.delivery else { return }
        let snapshot = incomplete.presentationSnapshot()

        let pro16 = snapshot.hosts.first { $0.id == "pro16" }
        let studio1 = snapshot.hosts.first { $0.id == "studio1" }
        #expect(pro16?.jobsTruncated == true)
        #expect(pro16?.capacityLabel.contains("job detail truncated") == true)
        #expect(studio1?.jobsTruncated == false)
        #expect(studio1?.capacityLabel.contains("truncated") == false)
    }

    @Test("Work state labels remain explicit and non-color dependent")
    func workStateLabels() {
        #expect(WorkState.allCases.map(\.title) == [
            "Active", "Waiting", "Completed", "Failed", "Blocked", "Stalled", "Unknown",
        ])
        #expect(WorkState.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }
}
