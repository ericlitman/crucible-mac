import Foundation

nonisolated protocol CrucibleCLIClient: Sendable {
    func liveFleetSnapshot() async throws -> LiveFleetDelivery
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
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CrucibleCLIClientError.executableUnavailable(executableURL.path)
        }

        let process = try LiveFleetCLIProcess.launch(
            executableURL: executableURL,
            arguments: Self.arguments,
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

        let delivery: LiveFleetDelivery
        do {
            delivery = try LiveFleetContractParser.parse(result.stdout)
        } catch {
            if status != 0 {
                let detail = result.stderrString.isEmpty ? error.localizedDescription : result.stderrString
                throw CrucibleCLIClientError.unexpectedExit(status, detail)
            }
            throw error
        }

        switch (status, delivery) {
        case (0, .snapshot):
            return delivery
        case (0, .error(let envelope)):
            throw CrucibleCLIClientError.contractMismatch("error envelope exited successfully: \(envelope.error.code)")
        case (_, .error):
            return delivery
        case (_, .snapshot):
            throw CrucibleCLIClientError.unexpectedExit(status, result.stderrString)
        }
    }

}
