import Foundation

nonisolated enum NotificationEpisodeAdmission: Equatable, Sendable {
    case admitted
    case alreadyTracked
    case capacityReached
}

nonisolated protocol NotificationDeliveryStore: Sendable {
    func contains(_ episodeID: String) -> Bool
    func admit(_ episodeID: String) -> NotificationEpisodeAdmission
    func record(_ episodeID: String)
    func abandon(_ episodeID: String)
}

nonisolated protocol NotificationEpisodeStore: NotificationDeliveryStore {
    func reconcile(authoritativeActiveEpisodeIDs: Set<String>)
}

nonisolated final class UserDefaultsNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    static let defaultCapacity = 512

    private let defaults: UserDefaults
    private let key: String
    private let capacity: Int
    private let lock = NSLock()
    private var admittedEpisodeIDs: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        key: String = "deliveredImportantConditionEpisodeIDs",
        capacity: Int = UserDefaultsNotificationEpisodeStore.defaultCapacity
    ) {
        precondition(capacity > 0, "Notification episode capacity must be positive")
        self.defaults = defaults
        self.key = key
        self.capacity = capacity
        normalizePersistedEpisodes()
    }

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { storedEpisodeIDs().contains(episodeID) }
    }

    func admit(_ episodeID: String) -> NotificationEpisodeAdmission {
        lock.withLock {
            let episodeIDs = storedEpisodeIDs()
            guard !episodeIDs.contains(episodeID),
                  !admittedEpisodeIDs.contains(episodeID) else { return .alreadyTracked }
            guard episodeIDs.count + admittedEpisodeIDs.count < capacity else {
                return .capacityReached
            }
            admittedEpisodeIDs.insert(episodeID)
            return .admitted
        }
    }

    func record(_ episodeID: String) {
        lock.withLock {
            precondition(
                admittedEpisodeIDs.remove(episodeID) != nil,
                "A notification episode must be admitted before it is recorded"
            )
            var episodeIDs = storedEpisodeIDs()
            precondition(
                episodeIDs.count < capacity,
                "An admitted notification episode must have durable ledger capacity"
            )
            episodeIDs.append(episodeID)
            persist(episodeIDs)
        }
    }

    func abandon(_ episodeID: String) {
        _ = lock.withLock { admittedEpisodeIDs.remove(episodeID) }
    }

    func reconcile(authoritativeActiveEpisodeIDs: Set<String>) {
        lock.withLock {
            persist(storedEpisodeIDs().filter(authoritativeActiveEpisodeIDs.contains))
        }
    }

    private func normalizePersistedEpisodes() {
        lock.withLock {
            let episodeIDs = storedEpisodeIDs()
            // Older builds had no bound, so normalize once at startup by
            // retaining the newest successful identities. Runtime admission
            // never evicts a recorded identity after this migration.
            let normalizedEpisodeIDs = Array(
                mostRecentUniqueEpisodeIDs(episodeIDs).suffix(capacity)
            )
            guard normalizedEpisodeIDs != episodeIDs else { return }
            defaults.set(normalizedEpisodeIDs, forKey: key)
        }
    }

    private func persist(_ episodeIDs: [String]) {
        let uniqueEpisodeIDs = mostRecentUniqueEpisodeIDs(episodeIDs)
        precondition(
            uniqueEpisodeIDs.count <= capacity,
            "Runtime notification persistence must never evict a successful identity"
        )
        defaults.set(uniqueEpisodeIDs, forKey: key)
    }

    private func mostRecentUniqueEpisodeIDs(_ episodeIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return episodeIDs.reversed().filter {
            seen.insert($0).inserted
        }.reversed()
    }

    private func storedEpisodeIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
