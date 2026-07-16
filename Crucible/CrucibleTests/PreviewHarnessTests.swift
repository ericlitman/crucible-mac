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
        #expect(!PreviewHarness.shouldLoadPreviewData(
            arguments: [
                "Crucible",
                PreviewHarness.previewArgument,
                PreviewHarness.incompatibleArgument,
            ],
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

    @Test("DEBUG incompatible proof selects a distinct truthful CLI response presentation")
    func incompatiblePresentation() {
        let presentation = PreviewHarness.initialPresentation(
            arguments: [
                "Crucible",
                PreviewHarness.previewArgument,
                PreviewHarness.incompatibleArgument,
            ]
        )

        #expect(presentation == PreviewFixtures.incompatiblePresentation)
        #expect(presentation.snapshot == PreviewFixtures.fleet)
        #expect(presentation.freshness == .incompatible)
        #expect(presentation.lastSuccessfulRefresh == PreviewFixtures.sourceTimestamp)
        #expect(presentation.errorMessage == "unsupported live-fleet contract version: 2")
        #expect(presentation.isPreviewData)
        #expect(presentation != PreviewFixtures.stalePresentation)
        #expect(presentation != PreviewFixtures.failedPresentation)
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
