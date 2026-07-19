import Foundation

nonisolated enum LiveFleetEventsDelivery: Equatable, Sendable {
    case events(LiveFleetEventsEnvelopeV1)
    case error(LiveFleetErrorEnvelopeV1)
}

nonisolated struct LiveFleetEventsCursorV1: Codable, Equatable, Sendable {
    let seq: Int
}

nonisolated struct LiveFleetEventsEnvelopeV1: Codable, Equatable, Sendable {
    let schema: String
    let contractVersion: Int
    let generatedAt: Date
    let cursor: LiveFleetEventsCursorV1
    let events: [LiveFleetEventV1]

    enum CodingKeys: String, CodingKey {
        case schema, cursor, events
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
    }
}

nonisolated struct LiveFleetEventV1: Codable, Equatable, Sendable {
    enum Importance: String, Codable, Sendable {
        case major, important
    }

    let schema: String
    let seq: Int
    let recordedAt: Date
    let queueDirectory: String?
    let id: String
    let transitionClass: String
    let itemID: String
    let attemptID: String?
    let toState: String?
    let action: String?
    let host: String?
    let reason: String?
    let failureClass: String?
    let remediation: String?
    let importance: Importance

    enum CodingKeys: String, CodingKey {
        case schema, seq, id, action, host, reason, remediation, importance
        case recordedAt = "recorded_at"
        case queueDirectory = "queue_dir"
        case transitionClass = "transition_class"
        case itemID = "item_id"
        case attemptID = "attempt_id"
        case toState = "to_state"
        case failureClass = "failure_class"
    }
}
