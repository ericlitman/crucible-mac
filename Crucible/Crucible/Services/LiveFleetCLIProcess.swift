import Darwin
import Foundation

nonisolated final class LiveFleetCLIProcess: @unchecked Sendable {
    private static let terminationGrace: Duration = .milliseconds(150)
    private static let cleanupLimit: Duration = .milliseconds(750)

    private let pid: pid_t
    private let capture: BoundedProcessCapture
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let stateLock = NSLock()
    private var exitStatus: Int32?
    private var cleanupDeadline: ContinuousClock.Instant?
    private var sentTermination = false
    private var sentKill = false

    private init(
        pid: pid_t,
        capture: BoundedProcessCapture,
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle
    ) {
        self.pid = pid
        self.capture = capture
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
    }

    static func launch(
        executableURL: URL,
        arguments: [String],
        maximumOutputBytes: Int
    ) throws -> LiveFleetCLIProcess {
        let capture = BoundedProcessCapture(limit: maximumOutputBytes)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { capture.receive($0.availableData, from: .stdout) }
        stderrHandle.readabilityHandler = { capture.receive($0.availableData, from: .stderr) }

        do {
            let pid = try spawn(
                executableURL: executableURL,
                arguments: arguments,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe
            )
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            return LiveFleetCLIProcess(
                pid: pid,
                capture: capture,
                stdoutHandle: stdoutHandle,
                stderrHandle: stderrHandle
            )
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            throw error
        }
    }

    func wait(timeout: TimeInterval) async throws -> Int32 {
        let executionDeadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while true {
            if let status = pollExitStatus(), !processGroupExists() { return status }
            let failure: Error
            if Task.isCancelled {
                failure = CancellationError()
            } else if ContinuousClock.now >= executionDeadline {
                failure = CrucibleCLIClientError.timedOut(timeout)
            } else {
                do {
                    try await Task.sleep(for: .milliseconds(20))
                    continue
                } catch {
                    failure = error
                }
            }
            await teardown(deadline: ContinuousClock.now.advanced(by: Self.cleanupLimit))
            throw failure
        }
    }

    func waitForEndOfOutput(timeout: TimeInterval) -> Bool {
        capture.waitForEndOfFiles(timeout: timeout)
    }

    func capturedOutput() -> (stdout: Data, stderrString: String, overflowed: Bool) {
        capture.result()
    }

    func closeOutput() {
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    private func teardown(deadline requestedDeadline: ContinuousClock.Instant) async {
        let (deadline, shouldSendTermination) = stateLock.withLock {
            let deadline = cleanupDeadline.map { min($0, requestedDeadline) } ?? requestedDeadline
            cleanupDeadline = deadline
            let shouldSignal = !sentTermination
            sentTermination = true
            return (deadline, shouldSignal)
        }
        if shouldSendTermination { signalGroup(SIGTERM) }

        let graceDeadline = min(deadline, ContinuousClock.now.advanced(by: Self.terminationGrace))
        while processGroupExists(), ContinuousClock.now < graceDeadline {
            _ = pollExitStatus()
            try? await Task.sleep(for: .milliseconds(10))
        }

        let shouldSendKill = stateLock.withLock {
            let shouldSignal = !sentKill
            sentKill = true
            return shouldSignal
        }
        if shouldSendKill, processGroupExists() { signalGroup(SIGKILL) }

        while processGroupExists(), ContinuousClock.now < deadline {
            _ = pollExitStatus()
            try? await Task.sleep(for: .milliseconds(10))
        }
        _ = pollExitStatus()
    }

    private func signalGroup(_ signal: Int32) {
        _ = Darwin.kill(-pid, signal)
    }

    private func processGroupExists() -> Bool {
        if Darwin.kill(-pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func pollExitStatus() -> Int32? {
        stateLock.withLock {
            if let exitStatus { return exitStatus }
            var rawStatus: Int32 = 0
            let result = Darwin.waitpid(pid, &rawStatus, WNOHANG)
            guard result == pid else { return nil }
            let signal = rawStatus & 0x7f
            exitStatus = signal == 0 ? (rawStatus >> 8) & 0xff : signal
            return exitStatus
        }
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String],
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&fileActions), operation: "initialize file actions")
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        try check(posix_spawnattr_init(&attributes), operation: "initialize attributes")
        defer { posix_spawnattr_destroy(&attributes) }

        let stdoutRead = stdoutPipe.fileHandleForReading.fileDescriptor
        let stdoutWrite = stdoutPipe.fileHandleForWriting.fileDescriptor
        let stderrRead = stderrPipe.fileHandleForReading.fileDescriptor
        let stderrWrite = stderrPipe.fileHandleForWriting.fileDescriptor
        try check(posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, STDOUT_FILENO), operation: "route stdout")
        try check(posix_spawn_file_actions_adddup2(&fileActions, stderrWrite, STDERR_FILENO), operation: "route stderr")
        for descriptor in [stdoutRead, stdoutWrite, stderrRead, stderrWrite] {
            try check(posix_spawn_file_actions_addclose(&fileActions, descriptor), operation: "close inherited pipe")
        }

        try check(posix_spawnattr_setpgroup(&attributes, 0), operation: "set process group")
        try check(
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)),
            operation: "enable process group"
        )

        let argv = [executableURL.path] + arguments
        let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = try withCStringArray(argv) { argvPointer in
            try withCStringArray(environment) { environmentPointer in
                executableURL.path.withCString { pathPointer in
                    posix_spawn(
                        &pid,
                        pathPointer,
                        &fileActions,
                        &attributes,
                        argvPointer,
                        environmentPointer
                    )
                }
            }
        }
        try check(result, operation: "launch \(executableURL.path)")
        return pid
    }

    private static func withCStringArray<Result>(
        _ strings: [String],
        body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) throws -> Result {
        let allocated = strings.map { strdup($0) }
        guard allocated.allSatisfy({ $0 != nil }) else {
            allocated.forEach { free($0) }
            throw CrucibleCLIClientError.launchFailed("could not allocate process arguments")
        }
        defer { allocated.forEach { free($0) } }
        var pointers = allocated + [nil]
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }

    private static func check(_ code: Int32, operation: String) throws {
        guard code == 0 else {
            throw CrucibleCLIClientError.launchFailed("\(operation): \(String(cString: strerror(code)))")
        }
    }
}
