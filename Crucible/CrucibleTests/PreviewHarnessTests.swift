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

    @Test("Proof surface parsing accepts only named DEBUG surfaces")
    func proofSurfaceParsing() {
        #expect(PreviewHarness.proofSurface(arguments: ["Crucible", "--preview-surface=menu"]) == .menu)
        #expect(PreviewHarness.proofSurface(arguments: ["Crucible", "--preview-surface=dashboard"]) == .dashboard)
        #expect(PreviewHarness.proofSurface(arguments: ["Crucible", "--preview-surface=unknown"]) == nil)
        #expect(PreviewHarness.proofSurface(arguments: ["Crucible"]) == nil)
    }

    @Test("Proof appearance parsing accepts only named DEBUG appearances")
    func proofAppearanceParsing() {
        #expect(PreviewHarness.proofAppearance(arguments: ["Crucible", "--preview-appearance=light"]) == .light)
        #expect(PreviewHarness.proofAppearance(arguments: ["Crucible", "--preview-appearance=dark"]) == .dark)
        #expect(PreviewHarness.proofAppearance(arguments: ["Crucible", "--preview-appearance=system"]) == nil)
        #expect(PreviewHarness.proofAppearance(arguments: ["Crucible"]) == nil)
    }
}
