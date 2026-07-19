import Foundation

nonisolated protocol CrucibleCLIClient: Sendable {
    func liveFleetSnapshot() async throws -> LiveFleetDelivery
    func liveFleetEvents(since seq: Int?) async throws -> LiveFleetEventsDelivery
}

nonisolated enum CrucibleCLIClientError: Error, Equatable, LocalizedError, Sendable {
    case executableUnavailable(String)
    case launchFailed(String)
    case timedOut(TimeInterval)
    case outputTooLarge(Int)
    case unexpectedExit(Int32, String)
    case contractMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .executableUnavailable(path): "Crucible CLI is unavailable at \(path)."
        case let .launchFailed(detail): "Crucible CLI could not launch: \(detail)"
        case let .timedOut(seconds): "Crucible CLI did not finish within \(seconds.formatted()) seconds."
        case let .outputTooLarge(limit): "Crucible CLI output exceeded the \(limit)-byte safety limit."
        case let .unexpectedExit(status, detail): "Crucible CLI exited with status \(status): \(detail)"
        case let .contractMismatch(detail): "Crucible CLI contract mismatch: \(detail)"
        }
    }
}

nonisolated struct ProcessCrucibleCLIClient: CrucibleCLIClient {
    static let installedExecutableURL = URL(fileURLWithPath: "/Users/ericlitman/.local/bin/operator-supervisor")
    static let arguments = ["live-fleet", "--contract-version", "1", "--format", "json"]

    static func eventsArguments(since seq: Int?) -> [String] {
        var arguments = ["live-fleet", "--events"]
        if let seq { arguments += ["--since", String(seq)] }
        arguments += ["--contract-version", "1", "--format", "json"]
        return arguments
    }

    let executableURL: URL
    let timeout: TimeInterval
    let maximumOutputBytes: Int

    init(
        executableURL: URL = installedExecutableURL,
        timeout: TimeInterval = 25,
        maximumOutputBytes: Int = 1_048_576
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    func liveFleetSnapshot() async throws -> LiveFleetDelivery {
        let result = try await invoke(arguments: Self.arguments)
        let delivery: LiveFleetDelivery
        do {
            delivery = try LiveFleetContractParser.parse(result.stdout)
        } catch {
            if result.status != 0 {
                let detail = result.stderrString.isEmpty ? error.localizedDescription : result.stderrString
                throw CrucibleCLIClientError.unexpectedExit(result.status, detail)
            }
            throw error
        }

        switch (result.status, delivery) {
        case (0, .snapshot):
            return delivery
        case (0, .error(let envelope)):
            throw CrucibleCLIClientError.contractMismatch("error envelope exited successfully: \(envelope.error.code)")
        case (_, .error):
            return delivery
        case (_, .snapshot):
            throw CrucibleCLIClientError.unexpectedExit(result.status, result.stderrString)
        }
    }

    func liveFleetEvents(since seq: Int?) async throws -> LiveFleetEventsDelivery {
        let result = try await invoke(arguments: Self.eventsArguments(since: seq))
        let delivery: LiveFleetEventsDelivery
        do {
            delivery = try LiveFleetContractParser.parseEvents(result.stdout)
        } catch {
            if result.status != 0 {
                let detail = result.stderrString.isEmpty ? error.localizedDescription : result.stderrString
                throw CrucibleCLIClientError.unexpectedExit(result.status, detail)
            }
            throw error
        }

        switch (result.status, delivery) {
        case (0, .events):
            return delivery
        case (0, .error(let envelope)):
            throw CrucibleCLIClientError.contractMismatch("error envelope exited successfully: \(envelope.error.code)")
        case (_, .error):
            return delivery
        case (_, .events):
            throw CrucibleCLIClientError.unexpectedExit(result.status, result.stderrString)
        }
    }

    private func invoke(arguments: [String]) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CrucibleCLIClientError.executableUnavailable(executableURL.path)
        }

        let process = try LiveFleetCLIProcess.launch(
            executableURL: executableURL,
            arguments: arguments,
            maximumOutputBytes: maximumOutputBytes
        )
        defer { process.closeOutput() }
        let status = try await process.wait(timeout: timeout)

        guard process.waitForEndOfOutput(timeout: 1) else {
            throw CrucibleCLIClientError.contractMismatch("CLI output streams did not close after process termination")
        }
        try Task.checkCancellation()

        let result = process.capturedOutput()
        guard !result.overflowed else {
            throw CrucibleCLIClientError.outputTooLarge(maximumOutputBytes)
        }

        return CommandResult(status: status, stdout: result.stdout, stderrString: result.stderrString)
    }

    private struct CommandResult {
        let status: Int32
        let stdout: Data
        let stderrString: String
    }
}
