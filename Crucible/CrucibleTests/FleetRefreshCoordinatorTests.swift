import Testing
@testable import Crucible

struct FleetRefreshCoordinatorTests {
    @Test("Concurrent refresh callers share one CLI task")
    func coalesces() async throws {
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            delay: .milliseconds(100)
        )
        let coordinator = FleetRefreshCoordinator(client: client)

        async let first = coordinator.refresh()
        async let second = coordinator.refresh()
        async let third = coordinator.refresh()
        _ = try await (first, second, third)

        #expect(await client.callCount() == 1)
    }

    @Test("A completed refresh releases the coalescing slot")
    func sequentialRefreshes() async throws {
        let client = StubCLIClient(delivery: try LiveFleetFixture.healthy.delivery)
        let coordinator = FleetRefreshCoordinator(client: client)

        _ = try await coordinator.refresh()
        _ = try await coordinator.refresh()

        #expect(await client.callCount() == 2)
    }
}
