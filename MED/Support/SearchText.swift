import Foundation

/// Text folding used everywhere two names have to be compared: autocomplete,
/// duplicate detection, and later the filename matcher in stage 6.
///
/// Turkish needs explicit handling. Unicode diacritic folding turns `ğ`, `ş`,
/// `ç`, `ö`, `ü` into their plain letters on its own, but `ı` (U+0131) is a
/// base letter with nothing to strip, so it would never fold to `i` — meaning
/// "Biyofizik" and "BİYOFİZİK" would not match. The map below closes that gap.
enum SearchText {
    private static let turkishLetters: [Character: Character] = [
        "ı": "i", "İ": "i", "I": "i",
        "ğ": "g", "Ğ": "g",
        "ş": "s", "Ş": "s",
        "ç": "c", "Ç": "c",
        "ö": "o", "Ö": "o",
        "ü": "u", "Ü": "u",
        "â": "a", "Â": "a",
        "î": "i", "Î": "i",
        "û": "u", "Û": "u",
    ]

    /// A comparable form of `text`: Turkish letters flattened, case and
    /// remaining diacritics ignored, surrounding whitespace dropped.
    static func fold(_ text: String) -> String {
        String(text.map { turkishLetters[$0] ?? $0 })
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the two names should be treated as the same name.
    static func sameName(_ one: String, _ other: String) -> Bool {
        fold(one) == fold(other)
    }

    /// True when `query` appears anywhere in `text`. An empty query matches.
    static func contains(_ text: String, query: String) -> Bool {
        let needle = fold(query)
        guard !needle.isEmpty else { return true }
        return fold(text).contains(needle)
    }
}
