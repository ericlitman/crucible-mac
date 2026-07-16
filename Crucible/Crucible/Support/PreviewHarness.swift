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
