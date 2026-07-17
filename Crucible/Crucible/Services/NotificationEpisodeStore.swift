import Foundation

nonisolated protocol NotificationEpisodeStore: Sendable {
    func contains(_ episodeID: String) -> Bool
    func record(_ episodeID: String)
}

nonisolated final class UserDefaultsNotificationEpisodeStore: NotificationEpisodeStore, @unchecked Sendable {
    static let defaultLimit = 256

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = "deliveredImportantConditionEpisodeIDs",
        limit: Int = defaultLimit
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(1, limit)
    }

    func contains(_ episodeID: String) -> Bool {
        lock.withLock { storedEpisodeIDs().contains(episodeID) }
    }

    func record(_ episodeID: String) {
        lock.withLock {
            var episodeIDs = storedEpisodeIDs().filter { $0 != episodeID }
            episodeIDs.append(episodeID)
            if episodeIDs.count > limit {
                episodeIDs.removeFirst(episodeIDs.count - limit)
            }
            defaults.set(episodeIDs, forKey: key)
        }
    }

    private func storedEpisodeIDs() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
