actor FleetRefreshCoordinator {
    private let client: any CrucibleCLIClient
    private var inFlight: Task<LiveFleetDelivery, Error>?

    init(client: any CrucibleCLIClient) {
        self.client = client
    }

    func refresh() async throws -> LiveFleetDelivery {
        if let inFlight { return try await inFlight.value }

        let task = Task { try await client.liveFleetSnapshot() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
