import Foundation
import Darwin
import Testing
@testable import Crucible

struct CrucibleCLIClientTests {
    @Test("Production client uses the fixed installed wrapper and exact versioned argv")
    func productionBoundary() {
        #expect(ProcessCrucibleCLIClient.installedExecutableURL.path == "/Users/ericlitman/.local/bin/operator-supervisor")
        #expect(ProcessCrucibleCLIClient.arguments == ["live-fleet", "--contract-version", "1", "--format", "json"])
    }

    @Test("Process adapter invokes the executable directly with exact argv")
    func exactInvocation() async throws {
        let temp = try TemporaryCLI()
        let argumentsFile = temp.directory.appending(path: "arguments.txt")
        let environmentFile = temp.directory.appending(path: "environment.txt")
        let workingDirectoryFile = temp.directory.appending(path: "working-directory.txt")
        let fixture = try temp.copyFixture(.healthy)
        let executable = try temp.executable("""
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsFile.path)'
        printf '%s' "$HOME" > '\(environmentFile.path)'
        pwd > '\(workingDirectoryFile.path)'
        cat '\(fixture.path)'
        """)
        let delivery = try await ProcessCrucibleCLIClient(executableURL: executable).liveFleetSnapshot()

        guard case .snapshot = delivery else {
            Issue.record("Expected snapshot")
            return
        }
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(arguments == ProcessCrucibleCLIClient.arguments)
        #expect(try String(contentsOf: environmentFile, encoding: .utf8) == ProcessInfo.processInfo.environment["HOME"])
        #expect(
            try String(contentsOf: workingDirectoryFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) == FileManager.default.currentDirectoryPath
        )
    }

    @Test("Typed nonzero CLI envelope is preserved for the state reducer")
    func nonzeroEnvelope() async throws {
        let temp = try TemporaryCLI()
        let fixture = try temp.copyFixture(.failed)
        let executable = try temp.executable("""
        #!/bin/sh
        cat '\(fixture.path)'
        exit 4
        """)
        let delivery = try await ProcessCrucibleCLIClient(executableURL: executable).liveFleetSnapshot()

        guard case let .error(envelope) = delivery else {
            Issue.record("Expected error envelope")
            return
        }
        #expect(envelope.error.kind == .failed)
    }

    @Test("Missing wrapper reports a useful unavailable error")
    func missingExecutable() async {
        let client = ProcessCrucibleCLIClient(executableURL: URL(fileURLWithPath: "/definitely/missing/operator-supervisor"))
        await #expect(throws: CrucibleCLIClientError.executableUnavailable("/definitely/missing/operator-supervisor")) {
            try await client.liveFleetSnapshot()
        }
    }

    @Test("Process timeout force-kills a CLI that ignores SIGTERM")
    func timeout() async throws {
        let temp = try TemporaryCLI()
        let parentPIDFile = temp.directory.appending(path: "timeout-parent.pid")
        let childPIDFile = temp.directory.appending(path: "timeout-child.pid")
        let executable = try temp.executable("""
        #!/bin/sh
        trap '' TERM
        /bin/sleep 30 &
        child=$!
        printf '%s' "$$" > '\(parentPIDFile.path)'
        printf '%s' "$child" > '\(childPIDFile.path)'
        wait "$child"
        """)
        let client = ProcessCrucibleCLIClient(executableURL: executable, timeout: 3)
        let started = ContinuousClock.now
        await #expect(throws: CrucibleCLIClientError.timedOut(3)) {
            try await client.liveFleetSnapshot()
        }
        let parentPID = try await processID(from: parentPIDFile)
        let childPID = try await processID(from: childPIDFile)
        #expect(ContinuousClock.now - started < .seconds(4.5))
        #expect(!processIsAlive(parentPID))
        #expect(!processIsAlive(childPID))
    }

    @Test("Task cancellation force-kills a CLI that ignores SIGTERM")
    func cancellation() async throws {
        let temp = try TemporaryCLI()
        let parentPIDFile = temp.directory.appending(path: "cancellation-parent.pid")
        let childPIDFile = temp.directory.appending(path: "cancellation-child.pid")
        let executable = try temp.executable("""
        #!/bin/sh
        trap '' TERM
        /bin/sleep 30 &
        child=$!
        printf '%s' "$$" > '\(parentPIDFile.path)'
        printf '%s' "$child" > '\(childPIDFile.path)'
        wait "$child"
        """)
        let client = ProcessCrucibleCLIClient(executableURL: executable, timeout: 10)
        let task = Task { try await client.liveFleetSnapshot() }
        let parentPID = try await processID(from: parentPIDFile)
        let childPID = try await processID(from: childPIDFile)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
        #expect(!processIsAlive(parentPID))
        #expect(!processIsAlive(childPID))
    }

    @Test("Repeated timeout cleanup observes one stable absolute deadline")
    func repeatedTimeoutBound() async throws {
        let temp = try TemporaryCLI()
        let executable = try temp.executable("""
        #!/bin/sh
        trap '' TERM
        /bin/sleep 30 &
        wait "$!"
        """)
        let client = ProcessCrucibleCLIClient(executableURL: executable, timeout: 0.5)

        for _ in 0..<3 {
            let started = ContinuousClock.now
            await #expect(throws: CrucibleCLIClientError.timedOut(0.5)) {
                try await client.liveFleetSnapshot()
            }
            #expect(ContinuousClock.now - started < .seconds(1.5))
        }
    }

    @Test("Stdout and stderr capture remains bounded")
    func boundedOutput() async throws {
        let temp = try TemporaryCLI()
        let executable = try temp.executable("""
        #!/bin/sh
        printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        """)
        let client = ProcessCrucibleCLIClient(executableURL: executable, maximumOutputBytes: 32)
        await #expect(throws: CrucibleCLIClientError.outputTooLarge(32)) {
            try await client.liveFleetSnapshot()
        }
    }

    @Test("Malformed success and untyped nonzero exit never become fleet state")
    func malformedResults() async throws {
        let temp = try TemporaryCLI()
        let success = try temp.executable("""
        #!/bin/sh
        printf 'not-json'
        """, name: "success")
        await #expect(throws: LiveFleetContractError.self) {
            try await ProcessCrucibleCLIClient(executableURL: success).liveFleetSnapshot()
        }

        let failure = try temp.executable("""
        #!/bin/sh
        printf 'plain failure' >&2
        exit 7
        """, name: "failure")
        do {
            _ = try await ProcessCrucibleCLIClient(executableURL: failure).liveFleetSnapshot()
            Issue.record("Expected unexpected exit")
        } catch let error as CrucibleCLIClientError {
            guard case let .unexpectedExit(status, detail) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(status == 7)
            #expect(detail == "plain failure")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}

private func processID(from file: URL) async throws -> pid_t {
    for _ in 0..<400 {
        if let contents = try? String(contentsOf: file, encoding: .utf8),
           let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return pid
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw CocoaError(.fileReadNoSuchFile)
}

private func processIsAlive(_ pid: pid_t) -> Bool {
    Darwin.kill(pid, 0) == 0 || errno == EPERM
}

private final class TemporaryCLI {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "crucible-cli-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func copyFixture(_ fixture: LiveFleetFixture) throws -> URL {
        let destination = directory.appending(path: fixture.rawValue)
        try fixture.data.write(to: destination)
        return destination
    }

    func executable(_ contents: String, name: String = "operator-supervisor") throws -> URL {
        let url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
