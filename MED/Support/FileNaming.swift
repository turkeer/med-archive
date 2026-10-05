import Foundation

/// Reading meaning out of a file's name. Stage 6's folder scanner builds on
/// the same helpers.
enum FileNaming {
    /// Words that mean "this is a note of mine", matched as whole words.
    ///
    /// Whole words matter. The obvious rule — does the name contain "not" —
    /// is wrong often enough to be useless: an embryology slide called
    /// "Notochord gelişimi" contains it, so do "Prognoz", "Nota ve ritim" and
    /// "Denotasyon". Checked against thirteen realistic names, the substring
    /// rule misclassified five.
    private static let noteWords: Set<String> = [
        "not", "notu", "notum", "notlar", "notlari", "notlarim",
        "note", "notes", "ozet",
    ]

    /// The name without its extension.
    static func baseName(of fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// Folded words in the name, the extension dropped first. Turkish letters
    /// are flattened, so "NOTLARIM" and "notlarım" come out the same.
    static func tokens(in fileName: String) -> [String] {
        SearchText.tokens(in: baseName(of: fileName))
    }

    /// A guess at what a file is, from its name alone.
    static func kind(for fileName: String) -> LectureFileKind {
        Set(tokens(in: fileName)).isDisjoint(with: noteWords) ? .slide : .note
    }
}
