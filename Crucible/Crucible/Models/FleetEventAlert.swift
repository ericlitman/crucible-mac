import Foundation

nonisolated struct FleetEventAlert: Equatable, Sendable {
    let episodeID: String
    let title: String
    let subtitle: String
    let body: String
    let itemID: String
    let transitionClass: String
    let seq: Int

    init(event: LiveFleetEventV1) {
        episodeID = event.id
        itemID = event.itemID
        transitionClass = event.transitionClass
        seq = event.seq
        title = Self.title(for: event)
        subtitle = Self.subtitle(for: event)
        body = Self.body(for: event)
    }

    func notificationPayload() -> NotificationPayload {
        NotificationPayload(
            episodeID: episodeID,
            title: title,
            subtitle: subtitle,
            body: body,
            userInfo: [
                "kind": "event",
                "item_id": itemID,
                "transition_class": transitionClass,
                "seq": String(seq),
            ]
        )
    }

    private static func title(for event: LiveFleetEventV1) -> String {
        switch event.transitionClass {
        case "launched":
            if let host = event.host { return "Job \(event.itemID) launched on \(host)" }
            return "Job \(event.itemID) launched"
        case "held": return "\(event.itemID) held"
        case "reaped": return "\(event.itemID) reaped"
        case "validated": return "\(event.itemID) validated"
        case "publication": return "\(event.itemID) publication updated"
        case "review": return "\(event.itemID) review updated"
        case "merged": return "\(event.itemID) merged"
        case "recovered": return "\(event.itemID) recovered"
        case "failed_launch": return "\(event.itemID) failed to launch"
        case "parked": return "\(event.itemID) parked"
        default: return "\(event.itemID) \(humanized(event.transitionClass))"
        }
    }

    private static func subtitle(for event: LiveFleetEventV1) -> String {
        var context: [String] = []
        if let attemptID = event.attemptID { context.append("Attempt \(attemptID)") }
        if event.transitionClass != "launched", let host = event.host { context.append(host) }
        return context.isEmpty ? "Major fleet change" : context.joined(separator: " · ")
    }

    private static func body(for event: LiveFleetEventV1) -> String {
        var details: [String] = []
        if let reason = event.reason {
            details.append(sentence("\(event.itemID) \(failureVerb(for: event)): \(reason)"))
        } else if let toState = event.toState {
            details.append("State changed to \(humanized(toState)).")
        } else {
            details.append("Crucible recorded a \(humanized(event.transitionClass)) transition for \(event.itemID).")
        }
        if let action = event.action {
            details.append("Action: \(humanized(action)).")
        }
        if let remediation = event.remediation {
            details.append("Next: \(humanized(remediation)).")
        }
        return details.joined(separator: " ")
    }

    private static func failureVerb(for event: LiveFleetEventV1) -> String {
        switch event.transitionClass {
        case "failed_launch": "failed"
        case "held": "was held"
        case "parked": "was parked"
        default: "changed"
        }
    }

    private static func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }

    private static func sentence(_ value: String) -> String {
        guard let last = value.last, !".!?".contains(last) else { return value }
        return value + "."
    }
}
