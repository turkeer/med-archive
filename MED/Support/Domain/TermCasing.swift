import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Deterministic casing cleanup for glossary terms and definitions, applied at
/// display time only — nothing stored changes, so it is fully reversible.
///
/// Slides often SHOUT a term, or a whole definition, in capitals and the OCR
/// keeps it. This lowercases the shouting while leaving real abbreviations
/// (ATP, DNA, mRNA) alone. The one judgement it needs — is an all-caps token an
/// abbreviation, or just a word in capitals? — it answers by asking whether the
/// lower-cased token is a real dictionary word: "cell" is, so "CELL" → "cell";
/// "atp" is not, so "ATP" stays. The rule is pure and the dictionary is
/// injected, so it is tested without the OS; `TermCasingLive` supplies the real
/// one.
enum TermCasing {
    /// A term for display: fix each shouted token, then capitalise the first
    /// word if it is plainly lower-case.
    static func term(_ raw: String, isWord: (String) -> Bool) -> String {
        capitalizingFirstWord(fixTokens(raw.trimmingCharacters(in: .whitespaces), isWord: isWord))
    }

    /// A definition for display: de-shout it only when it is mostly capitals (a
    /// whole sentence in caps), then capitalise the first word. A normally-cased
    /// definition is left as it is, bar that first-letter touch.
    static func definition(_ raw: String, isWord: (String) -> Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let base = isMostlyUppercase(trimmed) ? fixTokens(trimmed, isWord: isWord) : trimmed
        return capitalizingFirstWord(base)
    }

    /// Fixes each whitespace-separated token independently and rejoins them.
    static func fixTokens(_ text: String, isWord: (String) -> Bool) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { fixToken(String($0), isWord: isWord) }
            .joined(separator: " ")
    }

    /// First, a known abbreviation is forced to its canonical casing whichever
    /// way it arrived ("dna"/"DNA"/"Dna" → "DNA", "mrna" → "mRNA"), so an
    /// embedded abbreviation written in lower-case is fixed too. Otherwise an
    /// all-caps token becomes lower-case when it is a real word or is long (a
    /// shout); a short non-word all-caps token (an unknown abbreviation) is
    /// kept. A token with any lower-case letter, or fewer than two letters, is
    /// left untouched — so "mRNA", "B-DNA", "pH", "A band" and "III" survive.
    private static func fixToken(_ token: String, isWord: (String) -> Bool) -> String {
        if let canonical = canonicalAbbreviation(token) { return canonical }
        let letters = token.filter { $0.isLetter }
        guard letters.count >= 2, letters.allSatisfy({ $0.isUppercase }) else { return token }
        let core = letters.lowercased()
        if isWord(core) { return token.lowercased() }
        if letters.count >= 6 { return token.lowercased() }
        return token
    }

    /// The canonical casing for a known abbreviation, matched case-insensitively
    /// on an all-letter token (and its "-s" plural), or `nil` when the token is
    /// not a listed abbreviation. Deterministic and closed: only the forms below
    /// are ever recased, so an ambiguous lowercase name (a gene like "ras", a
    /// word) is never touched.
    static func canonicalAbbreviation(_ token: String) -> String? {
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter }) else { return nil }
        let lower = token.lowercased()
        if let canonical = abbreviations[lower] { return canonical }
        if lower.hasSuffix("s"), let canonical = abbreviations[String(lower.dropLast())] {
            return canonical + "s"
        }
        return nil
    }

    /// Known abbreviations in their correct casing, keyed by the lower-cased
    /// form. Closed on purpose — extend as real cases turn up, never with
    /// anything whose casing is genuinely ambiguous.
    static let abbreviations: [String: String] = [
        "dna": "DNA", "rna": "RNA", "cdna": "cDNA", "mrna": "mRNA", "trna": "tRNA",
        "rrna": "rRNA", "mirna": "miRNA", "sirna": "siRNA", "snrna": "snRNA",
        "hnrna": "hnRNA", "snorna": "snoRNA",
        "atp": "ATP", "adp": "ADP", "amp": "AMP", "camp": "cAMP",
        "gtp": "GTP", "gdp": "GDP", "gmp": "GMP", "ctp": "CTP", "utp": "UTP",
        "nad": "NAD", "nadh": "NADH", "nadp": "NADP", "nadph": "NADPH", "fad": "FAD",
        "ph": "pH", "atpase": "ATPase", "gtpase": "GTPase",
        "rbc": "RBC", "wbc": "WBC", "ecm": "ECM", "mhc": "MHC", "er": "ER",
        "rer": "RER", "ser": "SER", "pcr": "PCR", "elisa": "ELISA",
        "mtoc": "MTOC", "serca": "SERCA",
    ]

    /// Whether the text is a shouted sentence: at least a few letters, more than
    /// 60% of them upper-case. A normally-cased sentence (only its first letters
    /// capitalised) stays well under that, so it is left alone.
    static func isMostlyUppercase(_ text: String) -> Bool {
        let letters = text.filter { $0.isLetter }
        guard letters.count >= 4 else { return false }
        let upper = letters.filter { $0.isUppercase }.count
        return Double(upper) / Double(letters.count) > 0.6
    }

    /// Upper-cases the first letter, but only when the first word is plainly
    /// lower-case — so "cytosol" becomes "Cytosol" while "pKa", "mRNA" and "ATP"
    /// are left exactly as they are.
    static func capitalizingFirstWord(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        let firstWord = text.prefix { !$0.isWhitespace }
        guard firstWord.allSatisfy({ $0.isLowercase || !$0.isLetter }) else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}

/// The live casing used by the views: the same rules, with the system
/// dictionary answering "is this a real word?". Main-actor and cached, because
/// the glossary asks about the same handful of tokens again and again as the
/// list redraws.
///
/// macOS'ta `NSSpellChecker`, iOS'ta `UITextChecker` — aynı soruya ("gerçek
/// kelime mi?") iki platformun kendi yazım denetleyicisiyle cevap.
#if canImport(AppKit)
@MainActor
enum TermCasingLive {
    private static var wordCache: [String: Bool] = [:]

    static func isWord(_ word: String) -> Bool {
        if let hit = wordCache[word] { return hit }
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        let known = range.location == NSNotFound
        wordCache[word] = known
        return known
    }

    static func term(_ raw: String) -> String { TermCasing.term(raw, isWord: isWord) }
    static func definition(_ raw: String) -> String { TermCasing.definition(raw, isWord: isWord) }
}
#elseif canImport(UIKit)
import UIKit

@MainActor
enum TermCasingLive {
    private static var wordCache: [String: Bool] = [:]
    private static let checker = UITextChecker()

    static func isWord(_ word: String) -> Bool {
        if let hit = wordCache[word] { return hit }
        let range = NSRange(location: 0, length: word.utf16.count)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false, language: "en"
        )
        let known = misspelled.location == NSNotFound
        wordCache[word] = known
        return known
    }

    static func term(_ raw: String) -> String { TermCasing.term(raw, isWord: isWord) }
    static func definition(_ raw: String) -> String { TermCasing.definition(raw, isWord: isWord) }
}
#endif
