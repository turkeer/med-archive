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

    // MARK: Term grouping — singular/plural and irregular variants

    func testRegularPluralPairMatchesSuffixes() {
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("acid", "acids"))
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("base", "bases"))
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("bone", "bones"))
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("body", "bodies"))
        // Order of the two does not matter.
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("acids", "acid"))
        // Multi-word: only the last word pluralises.
        XCTAssertTrue(GlossaryModel.isRegularPluralPair(
            "nuclear pore complex", "nuclear pore complexes"))
        // Turkish plural.
        XCTAssertTrue(GlossaryModel.isRegularPluralPair("hucre", "hucreler"))
    }

    func testRegularPluralPairRejectsNonPlurals() {
        // Different words that merely share a prefix.
        XCTAssertFalse(GlossaryModel.isRegularPluralPair("base", "basic"))
        XCTAssertFalse(GlossaryModel.isRegularPluralPair("cell", "cellular"))
        // An irregular pair is not a regular-suffix difference (handled by the
        // explicit list instead).
        XCTAssertFalse(GlossaryModel.isRegularPluralPair("nucleus", "nuclei"))
        // Identical, or too short to be a plural of something smaller.
        XCTAssertFalse(GlossaryModel.isRegularPluralPair("acid", "acid"))
        XCTAssertFalse(GlossaryModel.isRegularPluralPair("ab", "abs"))
    }

    func testIrregularPluralsAreGenuinelyIrregular() {
        // Each listed pair is a real singular/plural and NOT also a regular
        // suffix match, so the two mechanisms never fight over the same pair.
        for (singular, plural) in GlossaryModel.irregularPlurals {
            XCTAssertNotEqual(singular, plural)
            XCTAssertFalse(GlossaryModel.isRegularPluralPair(singular, plural),
                           "\(singular)/\(plural) should be irregular, not a regular plural")
        }
    }

    // MARK: Casing cleanup

    /// A stand-in dictionary: the ordinary words the tests shout, so "ATP" and
    /// "synthase" (unknown here) can be told from "cell" (known).
    private static func isWord(_ w: String) -> Bool {
        ["cell", "action", "potential", "the", "net", "flow", "of",
         "particles", "energy", "currency", "is", "band"].contains(w)
    }

    func testCasingKeepsAbbreviationsLowersShouts() {
        let isWord = Self.isWord
        // A shouted multi-word term is lowered and sentence-cased…
        XCTAssertEqual(TermCasing.term("ACTION POTENTIAL", isWord: isWord), "Action potential")
        // …a real but shouted single word too…
        XCTAssertEqual(TermCasing.term("CELL", isWord: isWord), "Cell")
        // …a long non-word all-caps token is treated as a shout (length rule)…
        XCTAssertEqual(TermCasing.term("ATP SYNTHASE", isWord: isWord), "ATP synthase")
        // …but a short non-word abbreviation is kept exactly.
        XCTAssertEqual(TermCasing.term("ATP", isWord: isWord), "ATP")
        XCTAssertEqual(TermCasing.term("DNA", isWord: isWord), "DNA")
    }

    func testCasingLeavesMixedCaseAndLoneLetters() {
        let isWord = Self.isWord
        XCTAssertEqual(TermCasing.term("mRNA", isWord: isWord), "mRNA")
        XCTAssertEqual(TermCasing.term("B-DNA", isWord: isWord), "B-DNA")
        XCTAssertEqual(TermCasing.term("pH", isWord: isWord), "pH")
        // "A band" / "I band": the lone capital letter is meaningful, kept.
        XCTAssertEqual(TermCasing.term("A band", isWord: isWord), "A band")
    }

    func testCasingDefinitionOnlyDeShoutsWhenMostlyCaps() {
        let isWord = Self.isWord
        // A shouted definition is lowered to sentence case, abbreviation kept.
        XCTAssertEqual(
            TermCasing.definition("ATP IS THE ENERGY CURRENCY", isWord: isWord),
            "ATP is the energy currency")
        // A normally-cased definition is untouched (bar the first-letter touch).
        let normal = "the net flow of particles"
        XCTAssertEqual(TermCasing.definition(normal, isWord: isWord), "The net flow of particles")
        // One that already reads correctly is left exactly as it is.
        let fine = "The net flow of particles"
        XCTAssertEqual(TermCasing.definition(fine, isWord: isWord), fine)
    }

    func testIsMostlyUppercase() {
        XCTAssertTrue(TermCasing.isMostlyUppercase("THE NET FLOW"))
        XCTAssertFalse(TermCasing.isMostlyUppercase("The net flow of particles"))
        XCTAssertFalse(TermCasing.isMostlyUppercase("ATP"))  // too few letters for a sentence
    }

    // MARK: Export

    func testMarkdownGroupsByLetterWithSources() {
        let items = [
            GlossaryExport.Item(term: "Axon", definitions: [
                GlossaryExport.Definition(text: "the nerve fibre of a neuron",
                                          sources: ["Neuro · p.3"])
            ]),
            GlossaryExport.Item(term: "Diffusion", definitions: [
                GlossaryExport.Definition(text: "net flow down a gradient", sources: [])
            ]),
        ]
        let md = GlossaryExport.markdown(items)
        XCTAssertTrue(md.hasPrefix("# Sözlük"))
        XCTAssertTrue(md.contains("**2 terim · 2 tanım**"))
        XCTAssertTrue(md.contains("## A"))
        XCTAssertTrue(md.contains("### Axon"))
        XCTAssertTrue(md.contains("the nerve fibre of a neuron"))
        XCTAssertTrue(md.contains("_Neuro · p.3_"))
        XCTAssertTrue(md.contains("## D"))
        XCTAssertTrue(md.contains("### Diffusion"))
    }

    func testLetterKeyBucketsNonLetters() {
        XCTAssertEqual(GlossaryExport.letterKey("Axon"), "A")
        XCTAssertEqual(GlossaryExport.letterKey("mRNA"), "M")
        XCTAssertEqual(GlossaryExport.letterKey("3' end"), "#")
    }

    func testPdfProducesANonEmptyDocument() {
        let items = [
            GlossaryExport.Item(term: "Axon", definitions: [
                GlossaryExport.Definition(text: "the nerve fibre of a neuron", sources: ["Neuro · p.3"])
            ]),
        ]
        let data = GlossaryExport.pdf(items)
        XCTAssertFalse(data.isEmpty)
        // A real PDF starts with the "%PDF" signature.
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
    }

    func testCasingFixesLowercaseAbbreviationsInTerm() {
        let isWord = Self.isWord
        // The reported case: a lower-cased abbreviation inside a term is fixed.
        XCTAssertEqual(TermCasing.term("alpha satellite dna", isWord: isWord),
                       "Alpha satellite DNA")
        // Mixed casing recovered from any input casing.
        XCTAssertEqual(TermCasing.canonicalAbbreviation("mrna"), "mRNA")
        XCTAssertEqual(TermCasing.canonicalAbbreviation("MRNA"), "mRNA")
        XCTAssertEqual(TermCasing.canonicalAbbreviation("DNA"), "DNA")
        // The "-s" plural keeps the canonical form.
        XCTAssertEqual(TermCasing.canonicalAbbreviation("rnas"), "RNAs")
        // An unlisted, ambiguous lowercase name is left alone.
        XCTAssertNil(TermCasing.canonicalAbbreviation("ras"))
        XCTAssertNil(TermCasing.canonicalAbbreviation("satellite"))
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
