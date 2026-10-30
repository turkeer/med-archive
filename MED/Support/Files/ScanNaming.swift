import Foundation

/// What a file's name says about the lecture it belongs to.
struct ScanFileName {
    /// Start of the day the name mentions, or `nil` when it mentions none.
    let date: Date?

    /// Everything the name says apart from the date. May be empty.
    let topic: String
}

/// Reading a date and a topic out of a file's name, and judging how close a
/// topic is to a lecture's title.
///
/// Kept apart from the scan itself so the two things that can be wrong here —
/// what a name means, and what to do about it — can be reasoned about one at a
/// time. Both are pure functions over strings: no files, no store.
enum ScanNaming {
    private struct DatePattern {
        let regex: NSRegularExpression

        /// `03-10-2025` as against `2025-10-03`. Day first is the Turkish
        /// convention, so an ambiguous `03-10-2025` reads as 3 October.
        let dayFirst: Bool
    }

    /// Separators are `-`, `_` and `.`, never a space: allowing spaces turns
    /// an innocent "Ders 1 2 2025.pdf" into a date.
    private static let patterns: [DatePattern] = {
        let specs: [(String, Bool)] = [
            (#"(\d{4})[-._](\d{1,2})[-._](\d{1,2})"#, false),
            (#"(?<!\d)(\d{1,2})[-._](\d{1,2})[-._](\d{4})(?!\d)"#, true),
            (#"(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)"#, false),
        ]

        return specs.compactMap { spec -> DatePattern? in
            guard let regex = try? NSRegularExpression(pattern: spec.0) else { return nil }
            return DatePattern(regex: regex, dayFirst: spec.1)
        }
    }()

    /// Trimmed from both ends of a topic: what is left over once the date is
    /// cut out of "2026-10-01 | Basic Principles".
    private static let edgeCharacters = CharacterSet(charactersIn: " |-_.\t")

    static func read(_ fileName: String) -> ScanFileName {
        let base = FileNaming.baseName(of: fileName)
        let text = base as NSString
        let whole = NSRange(location: 0, length: text.length)

        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: base, range: whole),
                  match.numberOfRanges == 4
            else { continue }

            let numbers = (1...3).map { Int(text.substring(with: match.range(at: $0))) ?? 0 }
            let year = pattern.dayFirst ? numbers[2] : numbers[0]
            let day = pattern.dayFirst ? numbers[0] : numbers[2]

            // A pattern can match and still not be a date — 2025-13-45 does.
            // Then the next pattern gets its turn, and failing all of them the
            // name simply has no date in it.
            guard let date = startOfDay(year: year, month: numbers[1], day: day) else { continue }

            let before = text.substring(to: match.range.location)
            let after = text.substring(from: match.range.location + match.range.length)

            return ScanFileName(date: date, topic: trim(before + " " + after))
        }

        return ScanFileName(date: nil, topic: trim(base))
    }

    /// Lenient calendars roll 31 February over into March rather than
    /// refusing it, so the components are read back and compared.
    private static func startOfDay(year: Int, month: Int, day: Int) -> Date? {
        guard (2000...2100).contains(year),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return nil }

        let readBack = calendar.dateComponents([.year, .month, .day], from: date)
        guard readBack.year == year, readBack.month == month, readBack.day == day else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: edgeCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Topic similarity

    /// 0 for nothing in common, 1 for the same topic.
    ///
    /// Word by word rather than character by character, and words count as the
    /// same when one is a prefix of the other. Turkish glues its suffixes on,
    /// so a file called "Enzimler" and a lecture called "Enzim kinetiği" are
    /// about the same thing while sharing no whole word; an edit distance over
    /// the whole string would miss that, and so would set intersection.
    static func similarity(_ one: String, _ other: String) -> Double {
        let left = SearchText.fold(one)
        let right = SearchText.fold(other)

        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        // "Kalp" against "Kalp Anatomisi": the file is named after part of the
        // topic, which is as good as evidence gets short of equality.
        if left.contains(right) || right.contains(left) { return 0.85 }

        let leftWords = Set(SearchText.tokens(in: one))
        let rightWords = Set(SearchText.tokens(in: other))
        guard !leftWords.isEmpty, !rightWords.isEmpty else { return 0 }

        let matchedLeft = leftWords.filter { word in
            rightWords.contains { sameWord(word, $0) }
        }
        let matchedRight = rightWords.filter { word in
            leftWords.contains { sameWord(word, $0) }
        }

        return Double(matchedLeft.count + matchedRight.count)
            / Double(leftWords.count + rightWords.count)
    }

    /// The four-letter floor keeps the prefix rule from declaring "de" and
    /// "deri" the same word.
    private static func sameWord(_ one: String, _ other: String) -> Bool {
        if one == other { return true }

        let shorter = one.count < other.count ? one : other
        let longer = one.count < other.count ? other : one

        return shorter.count >= 4 && longer.hasPrefix(shorter)
    }
}
