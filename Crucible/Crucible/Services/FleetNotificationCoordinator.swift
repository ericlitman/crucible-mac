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
        isAuthoritativeComplete: Bool,
        shouldContinue: @MainActor @Sendable () -> Bool = { true }
    ) async -> FleetNotificationResult {
        let alerts = ImportantConditionAlertPlanner.alerts(for: snapshot)
        if isAuthoritativeComplete {
            episodeStore.reconcile(
                authoritativeActiveEpisodeIDs: Set(snapshot.conditions.map(\.id))
            )
        }

        let authorizationState = await client.authorizationState()
        AppTelemetry.evaluatedNotifications(
            authorization: authorizationState.title,
            candidates: alerts.count
        )
        guard authorizationState == .authorized, shouldContinue() else {
            return FleetNotificationResult(
                authorizationState: authorizationState,
                deliveredEpisodeIDs: [],
                deliveryErrors: []
            )
        }

        var deliveredEpisodeIDs: [String] = []
        var deliveryErrors: [String] = []
        for alert in alerts {
            guard shouldContinue() else { break }
            guard !inFlightEpisodeIDs.contains(alert.episodeID) else { continue }
            switch episodeStore.admit(alert.episodeID) {
            case .alreadyTracked:
                continue
            case .capacityReached:
                deliveryErrors.append(
                    "\(alert.episodeID): Delivery history is full; this alert will retry after resolved conditions free capacity."
                )
                continue
            case .admitted:
                break
            }
            inFlightEpisodeIDs.insert(alert.episodeID)
            do {
                try await client.deliver(alert)
                episodeStore.record(alert.episodeID)
                deliveredEpisodeIDs.append(alert.episodeID)
            } catch {
                episodeStore.abandon(alert.episodeID)
                deliveryErrors.append("\(alert.episodeID): \(error.localizedDescription)")
            }
            inFlightEpisodeIDs.remove(alert.episodeID)
            guard shouldContinue() else { break }
        }

        AppTelemetry.completedNotificationDelivery(
            delivered: deliveredEpisodeIDs.count,
            errors: deliveryErrors.count
        )

        return FleetNotificationResult(
            authorizationState: authorizationState,
            deliveredEpisodeIDs: deliveredEpisodeIDs,
            deliveryErrors: deliveryErrors
        )
    }
}
