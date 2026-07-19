import Foundation

nonisolated final class FIFOEventDeliveryStore: NotificationDeliveryStore, @unchecked Sendable {
    static let defaultCapacity = 1_024
    static let defaultKey = "deliveredMajorEventIDs"

    private let defaults: UserDefaults
    private let key: String
    private let capacity: Int
    private let lock = NSLock()
    private var admittedEventIDs: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        key: String = FIFOEventDeliveryStore.defaultKey,
        capacity: Int = FIFOEventDeliveryStore.defaultCapacity
    ) {
        precondition(capacity > 0, "Event delivery capacity must be positive")
        self.defaults = defaults
        self.key = key
        self.capacity = capacity
        normalizePersistedEvents()
    }

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { storedEventIDs().contains(episodeID) }
    }

    func admit(_ episodeID: String) -> NotificationEpisodeAdmission {
        lock.withLock {
            guard !storedEventIDs().contains(episodeID),
                  !admittedEventIDs.contains(episodeID) else { return .alreadyTracked }
            admittedEventIDs.insert(episodeID)
            return .admitted
        }
    }

    func record(_ episodeID: String) {
        lock.withLock {
            precondition(
                admittedEventIDs.remove(episodeID) != nil,
                "An event must be admitted before it is recorded"
            )
            var eventIDs = storedEventIDs()
            eventIDs.append(episodeID)
            defaults.set(Array(mostRecentUniqueEventIDs(eventIDs).suffix(capacity)), forKey: key)
        }
    }

    func abandon(_ episodeID: String) {
        _ = lock.withLock { admittedEventIDs.remove(episodeID) }
    }

    private func normalizePersistedEvents() {
        lock.withLock {
            let eventIDs = storedEventIDs()
            let normalized = Array(mostRecentUniqueEventIDs(eventIDs).suffix(capacity))
            guard normalized != eventIDs else { return }
            defaults.set(normalized, forKey: key)
        }
    }

    private func mostRecentUniqueEventIDs(_ eventIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return eventIDs.reversed().filter { seen.insert($0).inserted }.reversed()
    }

    private func storedEventIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
