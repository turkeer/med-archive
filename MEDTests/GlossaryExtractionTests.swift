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

    func testUnwrapsFullyParenthesisedTerm() {
        // The slide parenthesised the whole entry; the term must come out
        // without its wrapping parens ("(Ligamentum nuchae)" → "Ligamentum
        // nuchae"), the case that slipped through before.
        let defs = DefinitionExtractor.definitions(
            path: "Anatomy/Spine.pdf", page: 1,
            text: "(Ligamentum nuchae): a strong median ligament at the back of the neck",
            isRecognised: false, vocabulary: []
        )
        XCTAssertEqual(defs.first?.term, "Ligamentum nuchae")
    }

    func testKeepsAcronymSuffixParentheses() {
        // A trailing acronym in parens is part of the term, not a wrapper, so
        // it must survive ("… kinases (Cdk)").
        let defs = DefinitionExtractor.definitions(
            path: "Biology/Cycle.pdf", page: 1,
            text: "Cyclin-dependent protein kinases (Cdk): enzymes that drive the cell cycle forward",
            isRecognised: false, vocabulary: []
        )
        XCTAssertEqual(defs.first?.term, "Cyclin-dependent protein kinases (Cdk)")
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

    // MARK: Deep verification (phase three)

    func testParseVerifiedKeepAndDemote() throws {
        let yes = try XCTUnwrap(GlossaryModel.parseVerifiedLine("YES"))
        XCTAssertTrue(yes.keep)

        let demoteTitle = try XCTUnwrap(GlossaryModel.parseVerifiedLine("NO title"))
        XCTAssertFalse(demoteTitle.keep)
        XCTAssertEqual(demoteTitle.reason, .title)

        // A bare NO with no reason word still demotes, bucketed as "other".
        let demoteBare = try XCTUnwrap(GlossaryModel.parseVerifiedLine("NO"))
        XCTAssertFalse(demoteBare.keep)
        XCTAssertEqual(demoteBare.reason, .other)
    }

    func testParseVerifiedTreatsGibberishAsNoAnswer() {
        // Anything that is neither YES nor NO is "no answer", so the entry is
        // left accepted rather than silently dropped.
        XCTAssertNil(GlossaryModel.parseVerifiedLine("maybe"))
        XCTAssertNil(GlossaryModel.parseVerifiedLine(""))
    }

    // MARK: Model-driven pipeline (whole-page reading)

    func testParseTermsListsTermsAndDropsNoise() {
        let answer = """
        Diffusion
        - Osmosis
        1) Active transport
        Diffusion
        NONE
        """
        let terms = GlossaryModel.parseTerms(answer)
        // Bullets and list numbering stripped, the duplicate folded away, and
        // a stray NONE line ignored.
        XCTAssertEqual(terms, ["Diffusion", "Osmosis", "Active transport"])
    }

    func testParseTermsEmptyOnNone() {
        XCTAssertTrue(GlossaryModel.parseTerms("NONE").isEmpty)
        XCTAssertTrue(GlossaryModel.parseTerms("").isEmpty)
    }

    func testParseDefinitionAcceptsAndRejects() {
        let good = GlossaryModel.parseDefinition(
            "the net flow of particles from high to low concentration", term: "Diffusion")
        XCTAssertEqual(good, "the net flow of particles from high to low concentration")

        XCTAssertNil(GlossaryModel.parseDefinition("NO", term: "Diffusion"))
        // Too short to be a definition.
        XCTAssertNil(GlossaryModel.parseDefinition("a flow", term: "Diffusion"))
    }

    func testParseSentenceRejectsNo() {
        XCTAssertNil(GlossaryModel.parseSentence("NO"))
        XCTAssertEqual(
            GlossaryModel.parseSentence("Osmosis is the diffusion of water across a membrane."),
            "Osmosis is the diffusion of water across a membrane.")
    }

    func testFingerprintIsStableAndSensitive() {
        // Same text → same fingerprint across calls (it must survive launches),
        // different text → different fingerprint (a changed page re-reads).
        XCTAssertEqual(GlossaryModel.fingerprint("Hücre zarı"), GlossaryModel.fingerprint("Hücre zarı"))
        XCTAssertNotEqual(GlossaryModel.fingerprint("Hücre zarı"), GlossaryModel.fingerprint("Hücre zarı "))
    }

    // MARK: Polish pass — term linking

    func testNormalizeStemStripsPlurals() {
        // English plural variants collapse to the same stem as the singular…
        XCTAssertEqual(GlossaryModel.normalizeStem("action potentials"),
                       GlossaryModel.normalizeStem("action potential"))
        XCTAssertEqual(GlossaryModel.normalizeStem("cells"), GlossaryModel.normalizeStem("cell"))
        XCTAssertEqual(GlossaryModel.normalizeStem("bodies"), GlossaryModel.normalizeStem("body"))
        // …Turkish plural too (folded form).
        XCTAssertEqual(GlossaryModel.normalizeStem("hucreler"), GlossaryModel.normalizeStem("hucre"))
    }

    func testNormalizeStemLeavesShortAndDoubleS() {
        // Too short to strip, and "-ss" is not a plural.
        XCTAssertEqual(GlossaryModel.normalizeStem("gas"), "gas")
        XCTAssertEqual(GlossaryModel.normalizeStem("mass"), "mass")
    }

    func testTermPairKeyIsOrderIndependent() {
        XCTAssertEqual(GlossaryModel.termPairKey("b", "a"), GlossaryModel.termPairKey("a", "b"))
        XCTAssertEqual(GlossaryModel.termPairKey("a", "b"), "a|b")
    }

    func testParseLinkedReadsYesNo() {
        XCTAssertEqual(GlossaryModel.parseLinkedLine("YES"), true)
        XCTAssertEqual(GlossaryModel.parseLinkedLine("NO"), false)
        XCTAssertNil(GlossaryModel.parseLinkedLine("maybe"))

        let pairs = [("action potential", "action potentials"), ("base", "bases")]
        let result = GlossaryModel.parseLinked("1) YES\n2) NO", pairs: pairs)
        XCTAssertEqual(result[GlossaryModel.termPairKey("action potential", "action potentials")], true)
        XCTAssertEqual(result[GlossaryModel.termPairKey("base", "bases")], false)
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
