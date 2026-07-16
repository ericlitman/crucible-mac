import Foundation

enum BuildCapabilities {
    #if DEBUG
    static let includesPreviewFixtures = true
    #else
    static let includesPreviewFixtures = false
    #endif
}

enum PreviewHarness {
    static let previewArgument = "--preview-data"
    static let staleArgument = "--preview-stale"
    static let errorArgument = "--preview-error"

    #if DEBUG
    enum ProofSurface: String, Equatable {
        case menu
        case dashboard
    }

    enum ProofAppearance: String, Equatable {
        case light
        case dark
    }

    static func proofSurface(arguments: [String] = ProcessInfo.processInfo.arguments) -> ProofSurface? {
        let prefix = "--preview-surface="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return ProofSurface(rawValue: String(argument.dropFirst(prefix.count)))
    }

    static func proofAppearance(arguments: [String] = ProcessInfo.processInfo.arguments) -> ProofAppearance? {
        let prefix = "--preview-appearance="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return ProofAppearance(rawValue: String(argument.dropFirst(prefix.count)))
    }
    #endif

    static func shouldLoadPreviewData(
        arguments: [String],
        fixturesIncluded: Bool = BuildCapabilities.includesPreviewFixtures
    ) -> Bool {
        fixturesIncluded && arguments.contains(previewArgument)
    }

    @MainActor
    static func initialPresentation(arguments: [String] = ProcessInfo.processInfo.arguments) -> FleetPresentation {
        #if DEBUG
        guard shouldLoadPreviewData(arguments: arguments) else {
            return .productionUnavailable
        }

        if arguments.contains(errorArgument) {
            return PreviewFixtures.failedPresentation
        }
        if arguments.contains(staleArgument) {
            return PreviewFixtures.stalePresentation
        }
        return PreviewFixtures.healthyPresentation
        #else
        return .productionUnavailable
        #endif
    }
}
