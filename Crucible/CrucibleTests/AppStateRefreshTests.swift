import Testing
@testable import Crucible

@MainActor
struct AppStateRefreshTests {
    @Test("Background and foreground cadence are exactly five minutes and one minute")
    func cadence() {
        let state = AppState(initialPresentation: .productionUnavailable)
        #expect(FleetRefreshCadence.background == 300)
        #expect(FleetRefreshCadence.foreground == 60)
        #expect(state.pollInterval == 300)

        state.menuBarDidAppear()
        #expect(state.pollInterval == 60)
        state.dashboardDidAppear()
        #expect(state.pollInterval == 60)
        state.menuBarDidDisappear()
        #expect(state.pollInterval == 60)
        state.dashboardDidDisappear()
        #expect(state.pollInterval == 300)
    }

    @Test("Fresh complete delivery becomes live and records last success")
    func completeFresh() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(contract) = try LiveFleetFixture.healthy.delivery else { return }

        state.apply(.snapshot(contract))

        #expect(state.presentation.freshness == .live(asOf: contract.sourceObservedAt!))
        #expect(state.presentation.lastSuccessfulRefresh == contract.generatedAt)
        #expect(state.snapshot?.hosts.map(\.id) == ["pro16"])
        #expect(state.presentation.errorMessage == nil)
    }

    @Test("Fresh partial delivery replaces an equally recent complete snapshot while remaining stale")
    func incompleteReplacesEquallyRecentComplete() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(healthy) = try LiveFleetFixture.healthy.delivery,
              case let .snapshot(incomplete) = try LiveFleetFixture.incomplete.delivery else { return }
        state.apply(.snapshot(healthy))
        let lastSuccess = state.presentation.lastSuccessfulRefresh

        state.apply(.snapshot(incomplete))

        #expect(state.snapshot?.hosts.map(\.id) == ["pro16", "studio1"])
        #expect(state.presentation.freshness == .stale(asOf: incomplete.sourceObservedAt!))
        #expect(state.presentation.lastSuccessfulRefresh == lastSuccess)
        #expect(state.presentation.errorMessage?.contains("showing the newest available partial snapshot") == true)
        #expect(state.presentation.errorMessage?.contains("host_unavailable:studio1") == true)
    }

    @Test("Fresh partial deliveries retain whichever usable snapshot is newest")
    func incompletePrefersNewestSnapshot() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(first) = try LiveFleetFixture.incomplete.delivery else { return }
        state.apply(.snapshot(first))

        var newerObject = try fixtureObject(.incomplete)
        newerObject["generated_at"] = "2026-07-16T12:01:05.000Z"
        newerObject["source_observed_at"] = "2026-07-16T12:01:00.000Z"
        var hosts = newerObject["hosts"] as! [[String: Any]]
        hosts[1]["id"] = "studio2"
        newerObject["hosts"] = hosts
        var completeness = newerObject["completeness"] as! [String: Any]
        completeness["reasons"] = ["host_unavailable:studio2", "monitor_refresh_partial"]
        newerObject["completeness"] = completeness
        guard case let .snapshot(newer) = try LiveFleetContractParser.parse(encodedFixture(newerObject)) else { return }

        state.apply(.snapshot(newer))

        #expect(state.snapshot?.hosts.map(\.id) == ["pro16", "studio2"])
        #expect(state.presentation.freshness == .stale(asOf: newer.sourceObservedAt!))
        #expect(state.presentation.errorMessage?.contains("showing the newest available partial snapshot") == true)
        #expect(state.presentation.errorMessage?.contains("host_unavailable:studio2") == true)
        let newerPresentation = state.presentation

        state.apply(.snapshot(first))

        #expect(state.presentation == newerPresentation)
    }

    @Test("An older fresh partial delivery does not downgrade a newer live snapshot")
    func olderIncompleteDoesNotDowngradeComplete() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        var newerObject = try fixtureObject()
        newerObject["generated_at"] = "2026-07-16T12:01:05.000Z"
        newerObject["source_observed_at"] = "2026-07-16T12:01:00.000Z"
        guard case let .snapshot(newerComplete) = try LiveFleetContractParser.parse(encodedFixture(newerObject)),
              case let .snapshot(olderIncomplete) = try LiveFleetFixture.incomplete.delivery else { return }
        state.apply(.snapshot(newerComplete))
        let livePresentation = state.presentation

        state.apply(.snapshot(olderIncomplete))

        #expect(state.presentation == livePresentation)
        #expect(state.presentation.freshness == .live(asOf: newerComplete.sourceObservedAt!))
    }

    @Test("An older fresh complete delivery does not replace a newer partial snapshot")
    func olderCompleteDoesNotDowngradePartial() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        var newerObject = try fixtureObject(.incomplete)
        newerObject["generated_at"] = "2026-07-16T12:01:05.000Z"
        newerObject["source_observed_at"] = "2026-07-16T12:01:00.000Z"
        guard case let .snapshot(newerIncomplete) = try LiveFleetContractParser.parse(encodedFixture(newerObject)),
              case let .snapshot(olderComplete) = try LiveFleetFixture.healthy.delivery else { return }
        state.apply(.snapshot(newerIncomplete))
        let partialPresentation = state.presentation

        state.apply(.snapshot(olderComplete))

        #expect(state.presentation == partialPresentation)
        #expect(state.presentation.freshness == .stale(asOf: newerIncomplete.sourceObservedAt!))
    }

    @Test("Stale and error deliveries preserve the newest usable partial snapshot")
    func staleAndErrorRetainIncompleteState() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(incomplete) = try LiveFleetFixture.incomplete.delivery else { return }
        state.apply(.snapshot(incomplete))
        let partial = state.snapshot

        var staleObject = try fixtureObject()
        staleObject["source_observed_at"] = "2026-07-16T12:20:00.000Z"
        var freshness = staleObject["freshness"] as! [String: Any]
        freshness["state"] = "stale"
        freshness["age_seconds"] = 700
        staleObject["freshness"] = freshness
        var hosts = staleObject["hosts"] as! [[String: Any]]
        hosts[0]["id"] = "different-host"
        staleObject["hosts"] = hosts
        guard case let .snapshot(stale) = try LiveFleetContractParser.parse(encodedFixture(staleObject)) else { return }

        state.apply(.snapshot(stale))

        #expect(state.snapshot == partial)
        #expect(state.presentation.freshness == .stale(asOf: incomplete.sourceObservedAt!))
        #expect(state.presentation.errorMessage?.contains("CLI data is stale") == true)

        state.apply(try LiveFleetFixture.failed.delivery)

        #expect(state.snapshot == partial)
        #expect(state.presentation.freshness == .stale(asOf: incomplete.sourceObservedAt!))
        #expect(state.presentation.errorMessage?.contains("invalid JSON") == true)
    }

    @Test("Fresh partial delivery remains visible as stale when no complete snapshot exists")
    func incompleteWithoutPriorState() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(incomplete) = try LiveFleetFixture.incomplete.delivery else { return }

        state.apply(.snapshot(incomplete))

        #expect(state.snapshot?.hosts.map(\.id) == ["pro16", "studio1"])
        #expect(state.presentation.freshness == .stale(asOf: incomplete.sourceObservedAt!))
        #expect(state.presentation.lastSuccessfulRefresh == nil)
    }

    @Test("Stale CLI snapshot is displayed as stale with source reason")
    func staleSnapshot() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(stale) = try LiveFleetFixture.stale.delivery else { return }

        state.apply(.snapshot(stale))

        #expect(state.presentation.freshness == .stale(asOf: stale.sourceObservedAt!))
        #expect(state.presentation.errorMessage?.contains("queue_heartbeat_stale") == true)
        #expect(state.snapshot != nil)
    }

    @Test("A differing stale response preserves the last known complete state")
    func staleRetainsCompleteState() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        guard case let .snapshot(healthy) = try LiveFleetFixture.healthy.delivery else { return }
        state.apply(.snapshot(healthy))
        let complete = state.snapshot
        let lastSuccess = state.presentation.lastSuccessfulRefresh

        var staleObject = try fixtureObject()
        staleObject["source_observed_at"] = "2026-07-16T12:20:00.000Z"
        var freshness = staleObject["freshness"] as! [String: Any]
        freshness["state"] = "stale"
        freshness["age_seconds"] = 700
        staleObject["freshness"] = freshness
        var hosts = staleObject["hosts"] as! [[String: Any]]
        hosts[0]["id"] = "different-host"
        staleObject["hosts"] = hosts
        guard case let .snapshot(stale) = try LiveFleetContractParser.parse(encodedFixture(staleObject)) else { return }

        state.apply(.snapshot(stale))

        #expect(state.snapshot == complete)
        #expect(state.snapshot?.hosts.map(\.id) == ["pro16"])
        #expect(state.presentation.freshness == .stale(asOf: complete!.sourceTimestamp))
        #expect(state.presentation.lastSuccessfulRefresh == lastSuccess)

        state.apply(try LiveFleetFixture.failed.delivery)
        #expect(state.snapshot == complete)
        #expect(state.presentation.lastSuccessfulRefresh == lastSuccess)
    }

    @Test("Error envelopes preserve prior state and last successful refresh")
    func errorRetention() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        state.apply(try LiveFleetFixture.healthy.delivery)
        let snapshot = state.snapshot
        let lastSuccess = state.presentation.lastSuccessfulRefresh

        state.apply(try LiveFleetFixture.failed.delivery)

        #expect(state.snapshot == snapshot)
        #expect(state.presentation.lastSuccessfulRefresh == lastSuccess)
        #expect(state.presentation.freshness == .stale(asOf: snapshot!.sourceTimestamp))
        #expect(state.presentation.errorMessage?.contains("invalid JSON") == true)
    }

    @Test("Incompatible response is explicit when no state can be retained")
    func incompatibleWithoutState() throws {
        let state = AppState(initialPresentation: .productionUnavailable)
        state.apply(try LiveFleetFixture.incompatible.delivery)

        #expect(state.snapshot == nil)
        #expect(state.presentation.freshness == .incompatible)
        #expect(state.presentation.lastSuccessfulRefresh == nil)
    }

    @Test("Refresh failures preserve state and surface useful errors")
    func thrownFailure() async throws {
        let healthy = try LiveFleetFixture.healthy.delivery
        let goodClient = StubCLIClient(delivery: healthy)
        let goodState = AppState(
            initialPresentation: .productionUnavailable,
            refreshCoordinator: FleetRefreshCoordinator(client: goodClient)
        )
        await goodState.refreshNow()

        let failingClient = StubCLIClient(delivery: healthy, shouldFail: true)
        let state = AppState(
            initialPresentation: goodState.presentation,
            refreshCoordinator: FleetRefreshCoordinator(client: failingClient)
        )
        await state.refreshNow()

        #expect(state.snapshot == goodState.snapshot)
        #expect(!state.presentation.freshness.isCurrent)
        #expect(state.presentation.errorMessage != nil)
    }

    @Test("Repeated immediate surface requests share the same refresh")
    func appearanceRefreshCoalesces() async throws {
        let client = StubCLIClient(
            delivery: try LiveFleetFixture.healthy.delivery,
            delay: .milliseconds(100)
        )
        let state = AppState(
            initialPresentation: .productionUnavailable,
            refreshCoordinator: FleetRefreshCoordinator(client: client)
        )
        state.startPolling()
        state.menuBarDidAppear()
        state.dashboardDidAppear()
        try await Task.sleep(for: .milliseconds(200))

        #expect(await client.callCount() == 1)
        state.stopPolling()
    }
}
