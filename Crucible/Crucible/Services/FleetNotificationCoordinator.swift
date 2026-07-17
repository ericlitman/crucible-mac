import Foundation

nonisolated struct FleetNotificationResult: Equatable, Sendable {
    let authorizationState: NotificationAuthorizationState
    let deliveredEpisodeIDs: [String]
    let deliveryErrors: [String]
}

@MainActor
final class FleetNotificationCoordinator {
    private let client: any SystemNotificationClient
    private let episodeStore: any NotificationEpisodeStore
    private var inFlightEpisodeIDs: Set<String> = []

    init(
        client: any SystemNotificationClient,
        episodeStore: any NotificationEpisodeStore
    ) {
        self.client = client
        self.episodeStore = episodeStore
    }

    func authorizationState() async -> NotificationAuthorizationState {
        await client.authorizationState()
    }

    func requestAuthorization() async throws -> NotificationAuthorizationState {
        try await client.requestAuthorization()
    }

    func process(
        _ snapshot: FleetSnapshot,
        isAuthoritativeComplete: Bool
    ) async -> FleetNotificationResult {
        let alerts = ImportantConditionAlertPlanner.alerts(for: snapshot)
        if isAuthoritativeComplete {
            episodeStore.reconcile(
                authoritativeActiveEpisodeIDs: Set(snapshot.conditions.map(\.id))
            )
        }

        let authorizationState = await client.authorizationState()
        guard authorizationState == .authorized else {
            return FleetNotificationResult(
                authorizationState: authorizationState,
                deliveredEpisodeIDs: [],
                deliveryErrors: []
            )
        }

        var deliveredEpisodeIDs: [String] = []
        var deliveryErrors: [String] = []
        for alert in alerts {
            guard !inFlightEpisodeIDs.contains(alert.episodeID),
                  !episodeStore.contains(alert.episodeID) else { continue }
            inFlightEpisodeIDs.insert(alert.episodeID)
            do {
                try await client.deliver(alert)
                episodeStore.record(alert.episodeID)
                deliveredEpisodeIDs.append(alert.episodeID)
            } catch {
                deliveryErrors.append("\(alert.episodeID): \(error.localizedDescription)")
            }
            inFlightEpisodeIDs.remove(alert.episodeID)
        }

        return FleetNotificationResult(
            authorizationState: authorizationState,
            deliveredEpisodeIDs: deliveredEpisodeIDs,
            deliveryErrors: deliveryErrors
        )
    }
}
