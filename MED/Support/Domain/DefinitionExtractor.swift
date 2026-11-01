import Foundation

/// A term and its explanation lifted from a slide, with the page it came from
/// so the reader can jump to it in context.
///
/// This is derived from the slide text, never typed: the glossary it feeds is
/// a reading of what your own slides already say, and every entry carries its
/// source so "where did this come from?" is one tap away.
struct SlideDefinition: Identifiable, Hashable {
    /// How much to trust that this really is a definition. The high ones read
    /// cleanly on their own; the uncertain ones are plausible but worth a
    /// glance, so the glossary keeps them out of the way until asked. (A later
    /// on-device model pass is meant to adjudicate exactly this uncertain tier.)
    enum Confidence {
        case high
        case uncertain
    }

    let term: String
    let definition: String

    /// The slide lines around this candidate — one before, and the rest of its
    /// block after — so the model can assemble the whole definition faithfully
    /// instead of judging a line that the colon pattern may have cut short.
    let context: String

    /// The stored path (relative to the library root, or absolute), the same
    /// form a file record and `SlideIndex` use, so it resolves to a slide.
    let path: String

    /// One-based, as a reader counts and as `SlidePageSelection` expects.
    let page: Int

    /// Read from the rendered image rather than the file's own text. OCR
    /// misreads, so a definition from it is a weaker claim.
    let isRecognised: Bool

    let confidence: Confidence

    var id: String { "\(path)#\(page)#\(term.lowercased())" }
}

/// Pulls candidate definitions out of slide text with nothing but patterns —
/// no model, works on every macOS. The colon pattern does the heavy lifting
/// because that is how slides actually write definitions: a term, a colon, and
/// the explanation either on the same line or on the lines below it ("Tissue:
/// / A tissue is an ensemble of similar cells…").
///
/// It errs towards keeping a candidate and marking it `.uncertain` rather than
/// dropping it: a strict filter that threw away real definitions to be rid of
/// the noise would defeat the point. Cleaning up the uncertain tier is the job
/// meant for the on-device model later.
enum DefinitionExtractor {
    /// Whole heads that are slide furniture, never a term.
    private static let furniture: Set<String> = [
        "note", "notes", "lesson", "lecture", "lecturer", "instructor", "date",
        "references", "reference", "summary", "introduction", "objective",
        "objectives", "outline", "contents", "content", "aim", "aims", "figure",
        "table", "total", "mcq", "source", "sources", "question", "questions",
        "case", "cases", "example", "examples", "locations",
    ]

    /// Heads beginning like a heading or a fragment, not a term.
    private static let rejectPrefixes: [String] = [
        "functions of ", "types of ", "list of ", "number of ", "overview of ",
        "introduction to ", "examples of ", "two ", "here ", "and ", "what ",
        "for ",
    ]

    private static let allowedTermScalars = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÇĞİıÖŞÜçğöşü()-/ ,")

    static func definitions(
        path: String,
        page: Int,
        text: String,
        isRecognised: Bool,
        vocabulary: Set<String>
    ) -> [SlideDefinition] {
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: " ")
        let lines = cleaned
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [SlideDefinition] = []

        for i in lines.indices {
            let line = lines[i]
            guard let colon = line.firstIndex(of: ":") else { continue }

            let head = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard let term = plausibleTerm(head) else { continue }

            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let raw: String

            if !rest.isEmpty {
                // "Term: definition" on one line; borrow the next line when the
                // inline part is too short to be the whole explanation.
                var text = rest
                if text.count < 40, i + 1 < lines.count,
                   !lines[i + 1].isEmpty, !lines[i + 1].contains(":") {
                    text += " " + lines[i + 1]
                }
                raw = text
            } else {
                // "Term:" then the explanation on the lines below, up to a
                // blank line or the next colon head.
                var accumulated: [String] = []
                var j = i + 1
                while j < lines.count, !lines[j].isEmpty, !lines[j].contains(":"),
                      accumulated.joined(separator: " ").count < 300 {
                    accumulated.append(lines[j])
                    j += 1
                }
                raw = accumulated.joined(separator: " ")
            }

            guard let definition = plausibleDefinition(raw) else { continue }

            result.append(SlideDefinition(
                term: term,
                definition: definition,
                context: context(of: lines, at: i),
                path: path,
                page: page,
                isRecognised: isRecognised,
                confidence: confidence(term: term, definition: definition, isRecognised: isRecognised, vocabulary: vocabulary)
            ))
        }

        return result
    }

    /// The block around the candidate line: one line before for context, then
    /// the candidate and the lines that follow it up to a blank line (the end
    /// of the thought on a slide), capped so a dense slide cannot send a wall
    /// of text to the model.
    private static func context(of lines: [String], at index: Int) -> String {
        let start = max(0, index - 1)
        var end = index
        var next = index + 1
        while next < lines.count, !lines[next].isEmpty, end - index < 7 {
            end = next
            next += 1
        }

        return String(lines[start...end].joined(separator: "\n").prefix(500))
    }

    private static func plausibleTerm(_ raw: String) -> String? {
        let term = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -•·*\t"))
        guard !term.isEmpty else { return nil }

        let low = term.lowercased()
        if low.contains("http") || low.contains("www") { return nil }
        if term.rangeOfCharacter(from: .decimalDigits) != nil { return nil }

        let words = term.split(separator: " ")
        guard (1...5).contains(words.count) else { return nil }
        guard term.filter(\.isLetter).count >= 3 else { return nil }
        guard term.count <= 45 else { return nil }

        if furniture.contains(low) { return nil }
        if rejectPrefixes.contains(where: { low.hasPrefix($0) }) { return nil }
        if term.unicodeScalars.contains(where: { !allowedTermScalars.contains($0) }) { return nil }

        return term
    }

    private static func plausibleDefinition(_ raw: String) -> String? {
        let collapsed = raw
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let definition = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " -•·*\t"))

        guard definition.count >= 25 else { return nil }
        guard definition.contains(" ") else { return nil }
        guard definition.filter(\.isLetter).count >= definition.count / 2 else { return nil }

        return definition
    }

    /// High when it reads like a real definition on its own: from the file's
    /// own text, a sensible length, and a term that is either a known slide
    /// word or a short capitalised phrase. Everything else plausible is kept as
    /// uncertain rather than thrown away.
    private static func confidence(
        term: String,
        definition: String,
        isRecognised: Bool,
        vocabulary: Set<String>
    ) -> SlideDefinition.Confidence {
        guard !isRecognised, (25...300).contains(definition.count) else { return .uncertain }

        let inVocabulary = vocabulary.contains(SearchText.fold(term))
        let words = term.split(separator: " ").count
        let startsUpper = term.first?.isUppercase ?? false

        if inVocabulary || (words <= 3 && startsUpper) {
            return .high
        }
        return .uncertain
    }
}
