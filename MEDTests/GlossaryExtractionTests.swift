import XCTest
@testable import MED

/// The pure shaping and filtering the glossary pipeline runs on every
/// candidate — term cleanup, the fragment and circular-definition guards, the
/// passage hallucination guard, and the consensus vote. These used to be
/// checked by eye against the live cache; here they are asserted.
@MainActor
final class GlossaryExtractionTests: XCTestCase {

    // MARK: Term shape

    func testStripListMarkerDropsEnumeration() {
        XCTAssertEqual(DefinitionExtractor.stripListMarker("c) Holocrine secretion"), "Holocrine secretion")
        XCTAssertEqual(DefinitionExtractor.stripListMarker("1) Cohesion"), "Cohesion")
        XCTAssertEqual(DefinitionExtractor.stripListMarker("iv. Something"), "Something")
    }

    func testStripListMarkerKeepsBareLetterTerms() {
        // "A band" / "I band" are real anatomy terms, not list items — there is
        // no ")" or "." after the letter, so they must survive untouched.
        XCTAssertEqual(DefinitionExtractor.stripListMarker("A band"), "A band")
        XCTAssertEqual(DefinitionExtractor.stripListMarker("I band"), "I band")
    }

    func testNormalizeTermCasing() {
        XCTAssertEqual(GlossaryModel.normalizeTerm("denaturation"), "Denaturation")
        XCTAssertEqual(GlossaryModel.normalizeTerm("GENOME"), "Genome")
    }

    func testNormalizeTermLeavesAcronymsAndMixedCase() {
        XCTAssertEqual(GlossaryModel.normalizeTerm("DNA"), "DNA")
        XCTAssertEqual(GlossaryModel.normalizeTerm("B-DNA"), "B-DNA")
        XCTAssertEqual(GlossaryModel.normalizeTerm("MARs"), "MARs")
    }

    func testNormalizeTermStripsListLetterFromModelOutput() {
        XCTAssertEqual(GlossaryModel.normalizeTerm("b) Apocrine secretion"), "Apocrine secretion")
    }

    // MARK: Definition shape

    func testSelfContainedRejectsFragments() {
        XCTAssertFalse(GlossaryModel.isSelfContained("repeating units", term: "Nucleosomes"))
        XCTAssertFalse(GlossaryModel.isSelfContained("that are mirror images of each other", term: "Stereoisomer"))
        XCTAssertFalse(GlossaryModel.isSelfContained("this group of proteins is", term: "Heat shock proteins"))
    }

    func testSelfContainedAcceptsRealDefinition() {
        XCTAssertTrue(GlossaryModel.isSelfContained(
            "the net flow of particles from regions of high to low concentration",
            term: "Diffusion"
        ))
    }

    func testStripNamingTailRemovesEchoedTerm() {
        let stripped = GlossaryModel.stripNamingTail(
            "the products of endocrine glands are called hormones",
            term: "Hormones"
        )
        XCTAssertEqual(stripped, "the products of endocrine glands")
    }

    func testStripNamingTailLeavesUnrelatedClause() {
        // The tail names something other than the term, so nothing is cut.
        let text = "a receptor that is called upon by its ligand"
        XCTAssertEqual(GlossaryModel.stripNamingTail(text, term: "Enzyme"), text)
    }

    func testTermAppearsGuard() {
        let passage = "Endocytosis is a process by which cells internalize the membrane."
        XCTAssertTrue(GlossaryModel.termAppears("Endocytosis", in: passage))
        XCTAssertTrue(GlossaryModel.termAppears("Ribosome", in: "Ribosomes are assembled in the nucleolus."))
        XCTAssertFalse(GlossaryModel.termAppears("Mitochondrion", in: passage))
    }

    // MARK: Consensus

    func testConsensusKeepsMajorityTerm() {
        let fallback = Self.candidate()
        let ballots = [
            GlossaryModel.Verdict(accepted: true, term: "Diffusion", definition: "the net flow of particles down a gradient", reason: nil),
            GlossaryModel.Verdict(accepted: true, term: "diffusion", definition: "net flow of particles from high to low concentration regions", reason: nil),
            GlossaryModel.Verdict(accepted: true, term: "Diffuse", definition: "something unstable the model guessed once", reason: nil),
        ]
        let verdict = GlossaryModel.consensus(of: ballots, fallback: fallback)
        XCTAssertTrue(verdict.accepted)
        XCTAssertEqual(SearchText.fold(verdict.term), "diffusion")
        // The fullest of the agreeing definitions is the one kept.
        XCTAssertEqual(verdict.definition, "net flow of particles from high to low concentration regions")
    }

    func testConsensusRejectsBelowQuorum() {
        let fallback = Self.candidate()
        let single = [GlossaryModel.Verdict(accepted: true, term: "Diffusion", definition: "net flow down a gradient here", reason: nil)]
        XCTAssertFalse(GlossaryModel.consensus(of: single, fallback: fallback).accepted)

        let noAgreement = [
            GlossaryModel.Verdict(accepted: true, term: "Alpha", definition: "a definition long enough to pass", reason: nil),
            GlossaryModel.Verdict(accepted: true, term: "Beta", definition: "another definition long enough here", reason: nil),
            GlossaryModel.Verdict(accepted: true, term: "Gamma", definition: "a third definition of some length", reason: nil),
        ]
        XCTAssertFalse(GlossaryModel.consensus(of: noAgreement, fallback: fallback).accepted)
    }

    private static func candidate() -> SlideDefinition {
        SlideDefinition(
            term: "fallback",
            definition: "fallback definition",
            source: .sentence,
            context: "some passage context",
            path: "Course/Lecture.pdf",
            page: 1,
            isRecognised: false,
            confidence: .uncertain
        )
    }
}
