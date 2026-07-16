import Foundation

nonisolated final class BoundedProcessCapture: @unchecked Sendable {
    enum Stream { case stdout, stderr }

    private let lock = NSLock()
    private let completion = DispatchGroup()
    private let limit: Int
    private var stdout = Data()
    private var stderr = Data()
    private var overflowed = false
    private var stdoutFinished = false
    private var stderrFinished = false

    init(limit: Int) {
        self.limit = limit
        completion.enter()
        completion.enter()
    }

    func receive(_ data: Data, from stream: Stream) {
        guard !data.isEmpty else {
            finish(stream)
            return
        }
        lock.withLock {
            let remaining = max(0, limit - stdout.count - stderr.count)
            if data.count > remaining { overflowed = true }
            let accepted = data.prefix(remaining)
            switch stream {
            case .stdout: stdout.append(accepted)
            case .stderr: stderr.append(accepted)
            }
        }
    }

    func waitForEndOfFiles(timeout: TimeInterval) -> Bool {
        completion.wait(timeout: .now() + timeout) == .success
    }

    func result() -> (stdout: Data, stderrString: String, overflowed: Bool) {
        lock.withLock {
            (stdout, String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), overflowed)
        }
    }

    private func finish(_ stream: Stream) {
        let shouldLeave = lock.withLock {
            switch stream {
            case .stdout where !stdoutFinished:
                stdoutFinished = true
                return true
            case .stderr where !stderrFinished:
                stderrFinished = true
                return true
            default:
                return false
            }
        }
        if shouldLeave { completion.leave() }
    }
}
