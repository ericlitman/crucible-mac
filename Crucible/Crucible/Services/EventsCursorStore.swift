import Foundation

nonisolated final class EventsCursorStore: @unchecked Sendable {
    static let defaultKey = "liveFleetEventsCursorSeq"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = EventsCursorStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func cursorSeq() -> Int? {
        lock.withLock {
            guard let number = defaults.object(forKey: key) as? NSNumber else { return nil }
            let value = number.intValue
            return value >= 0 ? value : nil
        }
    }

    func advance(to seq: Int) {
        precondition(seq >= 0, "Live-fleet event cursor must be nonnegative")
        lock.withLock {
            let current = (defaults.object(forKey: key) as? NSNumber)?.intValue
            defaults.set(max(current ?? 0, seq), forKey: key)
        }
    }

    func store(_ seq: Int) {
        precondition(seq >= 0, "Live-fleet event cursor must be nonnegative")
        lock.withLock { defaults.set(seq, forKey: key) }
    }
}
