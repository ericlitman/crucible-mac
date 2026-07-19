import Foundation

nonisolated struct FleetNotificationResult: Equatable, Sendable {
    let authorizationState: NotificationAuthorizationState
    let deliveredEpisodeIDs: [String]
    let deliveryErrors: [String]
}

nonisolated struct FleetEventNotificationResult: Equatable, Sendable {
    let authorizationState: NotificationAuthorizationState
    let deliveredEventIDs: [String]
    let newCursor: Int?
    let deliveryErrors: [String]
}

@MainActor
final class FleetNotificationCoordinator {
    private let client: any SystemNotificationClient
    private let episodeStore: any NotificationEpisodeStore
    private let eventStore: any NotificationDeliveryStore
    private var inFlightEpisodeIDs: Set<String> = []

    init(
        client: any SystemNotificationClient,
        episodeStore: any NotificationEpisodeStore,
        eventStore: any NotificationDeliveryStore = FIFOEventDeliveryStore()
    ) {
        self.client = client
        self.episodeStore = episodeStore
        self.eventStore = eventStore
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

        let delivery = await deliver(
            alerts.map { $0.notificationPayload() },
            using: episodeStore,
            capacityError: "Delivery history is full; this alert will retry after resolved conditions free capacity.",
            stopsOnFailure: false,
            shouldContinue: shouldContinue
        )
        let deliveredEpisodeIDs = delivery.outcomes.compactMap { outcome in
            outcome.isDelivered ? outcome.episodeID : nil
        }
        let deliveryErrors = delivery.errors

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

    func processEvents(
        _ events: [LiveFleetEventV1],
        shouldContinue: @MainActor @Sendable () -> Bool = { true }
    ) async -> FleetEventNotificationResult {
        let majorEvents = events.filter { $0.importance == .major }
        let authorizationState = await client.authorizationState()
        AppTelemetry.evaluatedEventNotifications(
            authorization: authorizationState.title,
            candidates: majorEvents.count
        )

        let delivery: DeliveryLoopResult
        if authorizationState == .authorized, shouldContinue() {
            delivery = await deliver(
                majorEvents.map { FleetEventAlert(event: $0).notificationPayload() },
                using: eventStore,
                capacityError: "Major-event delivery history could not accept this event.",
                stopsOnFailure: true,
                shouldContinue: shouldContinue
            )
        } else {
            delivery = DeliveryLoopResult(outcomes: [], errors: [])
        }

        var outcomeByID: [String: DeliveryOutcome] = [:]
        for outcome in delivery.outcomes { outcomeByID[outcome.episodeID] = outcome }
        var newCursor: Int?
        for event in events {
            guard shouldContinue() else { break }
            if event.importance == .important {
                newCursor = max(newCursor ?? 0, event.seq)
                continue
            }
            guard let outcome = outcomeByID[event.id], outcome.reachedFinality else { break }
            newCursor = max(newCursor ?? 0, event.seq)
        }

        let deliveredEventIDs = delivery.outcomes.compactMap { outcome in
            outcome.isDelivered ? outcome.episodeID : nil
        }
        AppTelemetry.completedEventNotificationDelivery(
            delivered: deliveredEventIDs.count,
            errors: delivery.errors.count
        )
        return FleetEventNotificationResult(
            authorizationState: authorizationState,
            deliveredEventIDs: deliveredEventIDs,
            newCursor: newCursor,
            deliveryErrors: delivery.errors
        )
    }

    private func deliver(
        _ payloads: [NotificationPayload],
        using store: any NotificationDeliveryStore,
        capacityError: String,
        stopsOnFailure: Bool,
        shouldContinue: @MainActor @Sendable () -> Bool
    ) async -> DeliveryLoopResult {
        var outcomes: [DeliveryOutcome] = []
        var errors: [String] = []
        for payload in payloads {
            guard shouldContinue() else { break }
            guard !inFlightEpisodeIDs.contains(payload.episodeID) else {
                outcomes.append(DeliveryOutcome(episodeID: payload.episodeID, status: .deferred))
                if stopsOnFailure { break }
                continue
            }
            switch store.admit(payload.episodeID) {
            case .alreadyTracked:
                outcomes.append(DeliveryOutcome(episodeID: payload.episodeID, status: .alreadyTracked))
                continue
            case .capacityReached:
                outcomes.append(DeliveryOutcome(episodeID: payload.episodeID, status: .failed))
                errors.append("\(payload.episodeID): \(capacityError)")
                if stopsOnFailure { return DeliveryLoopResult(outcomes: outcomes, errors: errors) }
                continue
            case .admitted:
                break
            }
            inFlightEpisodeIDs.insert(payload.episodeID)
            do {
                try await client.deliver(payload)
                store.record(payload.episodeID)
                outcomes.append(DeliveryOutcome(episodeID: payload.episodeID, status: .delivered))
            } catch {
                store.abandon(payload.episodeID)
                outcomes.append(DeliveryOutcome(episodeID: payload.episodeID, status: .failed))
                errors.append("\(payload.episodeID): \(error.localizedDescription)")
            }
            inFlightEpisodeIDs.remove(payload.episodeID)
            if stopsOnFailure, outcomes.last?.reachedFinality == false { break }
            guard shouldContinue() else { break }
        }
        return DeliveryLoopResult(outcomes: outcomes, errors: errors)
    }

    private struct DeliveryLoopResult {
        let outcomes: [DeliveryOutcome]
        let errors: [String]
    }

    private struct DeliveryOutcome {
        enum Status: Equatable { case delivered, alreadyTracked, deferred, failed }

        let episodeID: String
        let status: Status

        var isDelivered: Bool { status == .delivered }
        var reachedFinality: Bool { status == .delivered || status == .alreadyTracked }
    }
}
