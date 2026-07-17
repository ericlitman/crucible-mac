import Foundation

nonisolated protocol NotificationEpisodeStore: Sendable {
    func contains(_ episodeID: String) -> Bool
    func record(_ episodeID: String)
    func reconcile(authoritativeActiveEpisodeIDs: Set<String>)
}

nonisolated final class UserDefaultsNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = "deliveredImportantConditionEpisodeIDs"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { storedEpisodeIDs().contains(episodeID) }
    }

    func record(_ episodeID: String) {
        lock.withLock {
            var episodeIDs = storedEpisodeIDs().filter { $0 != episodeID }
            episodeIDs.append(episodeID)
            defaults.set(episodeIDs, forKey: key)
        }
    }

    func reconcile(authoritativeActiveEpisodeIDs: Set<String>) {
        lock.withLock {
            let retainedEpisodeIDs = storedEpisodeIDs().filter(authoritativeActiveEpisodeIDs.contains)
            defaults.set(retainedEpisodeIDs, forKey: key)
        }
    }

    private func storedEpisodeIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
