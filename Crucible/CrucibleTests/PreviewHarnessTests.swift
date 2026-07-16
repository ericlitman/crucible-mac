import Testing
@testable import Crucible

@MainActor
struct PreviewHarnessTests {
    @Test("Preview requires both the DEBUG capability and explicit launch argument")
    func explicitOptIn() {
        #expect(PreviewHarness.shouldLoadPreviewData(
            arguments: ["Crucible", PreviewHarness.previewArgument],
            fixturesIncluded: true
        ))
        #expect(!PreviewHarness.shouldLoadPreviewData(
            arguments: ["Crucible"],
            fixturesIncluded: true
        ))
    }

    @Test("Release exclusion seam wins even when the preview argument is supplied")
    func releaseExclusionSeam() {
        #expect(!PreviewHarness.shouldLoadPreviewData(
            arguments: ["Crucible", PreviewHarness.previewArgument],
            fixturesIncluded: false
        ))
    }

    @Test("DEBUG launch harness labels fixture data")
    func previewPresentation() {
        let presentation = PreviewHarness.initialPresentation(
            arguments: ["Crucible", PreviewHarness.previewArgument]
        )

        #expect(presentation.isPreviewData)
        #expect(presentation.snapshot == PreviewFixtures.fleet)
        #expect(presentation.freshness == .preview(asOf: PreviewFixtures.sourceTimestamp))
    }
}
