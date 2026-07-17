import Foundation

nonisolated protocol NotificationEpisodeStore: Sendable {
    func contains(_ episodeID: String) -> Bool
    func record(_ episodeID: String)
    func reconcile(authoritativeActiveEpisodeIDs: Set<String>)
}

nonisolated final class UserDefaultsNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    static let defaultCapacity = 512

    private let defaults: UserDefaults
    private let key: String
    private let capacity: Int
    private let lock = NSLock()

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

    func record(_ episodeID: String) {
        lock.withLock {
            var episodeIDs = storedEpisodeIDs().filter { $0 != episodeID }
            episodeIDs.append(episodeID)
            persist(episodeIDs)
        }
    }

    func reconcile(authoritativeActiveEpisodeIDs: Set<String>) {
        lock.withLock {
            persist(storedEpisodeIDs().filter(authoritativeActiveEpisodeIDs.contains))
        }
    }

    private func normalizePersistedEpisodes() {
        lock.withLock {
            let episodeIDs = storedEpisodeIDs()
            let normalizedEpisodeIDs = boundedUniqueEpisodeIDs(episodeIDs)
            guard normalizedEpisodeIDs != episodeIDs else { return }
            defaults.set(normalizedEpisodeIDs, forKey: key)
        }
    }

    private func persist(_ episodeIDs: [String]) {
        defaults.set(boundedUniqueEpisodeIDs(episodeIDs), forKey: key)
    }

    private func boundedUniqueEpisodeIDs(_ episodeIDs: [String]) -> [String] {
        var seen: Set<String> = []
        let mostRecentUniqueEpisodeIDs = episodeIDs.reversed().filter {
            seen.insert($0).inserted
        }.reversed()
        return Array(mostRecentUniqueEpisodeIDs.suffix(capacity))
    }

    private func storedEpisodeIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
