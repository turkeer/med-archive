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

    /// Where the candidate came from, which decides how the model treats it.
    /// `colon` candidates carry a term the slide's own "Term: …" structure
    /// gave us, so the model only confirms them. `sentence` candidates carry a
    /// term a regex guessed from running text — unreliable — so the model is
    /// asked to extract the real term itself rather than confirm the guess.
    enum Source {
        case colon
        case sentence
    }

    let term: String
    let definition: String
    let source: Source

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

    /// Stable across launches so the user's keep/hide marks survive a
    /// re-review. A colon candidate keys on its (reliable) term; a sentence
    /// candidate keys on its passage instead, because its regex term is a
    /// throwaway the model will replace — and two sentences on one page must
    /// not collide on the same fragment term.
    var id: String {
        switch source {
        case .colon:
            return "\(path)#\(page)#\(term.lowercased())"
        case .sentence:
            return "\(path)#\(page)#s:\(SearchText.fold(definition).prefix(48))"
        }
    }
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
        "case", "cases", "example", "examples", "locations", "textbook",
        "slide", "slides", "topic", "topics", "chapter",
    ]

    /// Heads beginning like a heading or a fragment, not a term.
    private static let rejectPrefixes: [String] = [
        "functions of ", "types of ", "list of ", "number of ", "overview of ",
        "introduction to ", "examples of ", "two ", "here ", "and ", "what ",
        "for ",
    ]

    /// Generic colon heads that label a block but are never the term
    /// themselves ("Definition: …", "Functions: …"). A definitional body under
    /// one is handed to the extraction path so the model names the real term;
    /// any other body — a bulleted list, a formula — is dropped. Without this,
    /// the literal word "Definition" became the headword and the real term,
    /// sitting inside the sentence, was lost.
    private static let labelHeads: Set<String> = [
        "definition", "definitions", "function", "functions", "purpose",
        "study", "aim", "aims", "exp", "identify the following", "identify",
        "observation", "observations",
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
            // The colon pattern is the strongest signal, so it is tried first;
            // only when a line has no "term: explanation" shape do we look for
            // a definition written as a sentence ("… is called X", "X refers
            // to …").
            if let colon = colonCandidate(lines: lines, at: i, path: path, page: page, isRecognised: isRecognised, vocabulary: vocabulary) {
                result.append(colon)
            } else if let sentence = sentenceCandidate(lines: lines, at: i, path: path, page: page, isRecognised: isRecognised, vocabulary: vocabulary) {
                result.append(sentence)
            }
        }

        return result
    }

    /// The classic "Term: explanation" line (inline, or the term on its own
    /// with the explanation on the lines below). This is where most real
    /// definitions live on a slide.
    private static func colonCandidate(
        lines: [String], at i: Int, path: String, page: Int, isRecognised: Bool, vocabulary: Set<String>
    ) -> SlideDefinition? {
        let line = lines[i]
        guard let colon = line.firstIndex(of: ":") else { return nil }

        let head = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        // Clean the head first, so a bulleted or numbered label ("• Definition:")
        // is still recognised as a label. A non-label head must itself read as
        // a term; a label head ("Definition:") is not the term, so that check
        // is deferred to the body below, where the real term lives.
        let term = plausibleTerm(head)
        let isLabel = term.map { labelHeads.contains(SearchText.fold($0)) } ?? false
        guard term != nil else { return nil }

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

        guard let definition = plausibleDefinition(raw) else { return nil }

        if isLabel {
            // "Definition:", "Functions:" and the like label a block, not a
            // term. A prose body is routed to the extraction path so the model
            // names the real term from it (often the slide title just above,
            // carried in the context); a bulleted list or a formula under the
            // label has no single term to name, so it is dropped.
            guard bodyIsProse(raw) else { return nil }
            return SlideDefinition(
                term: head,
                definition: definition,
                source: .sentence,
                context: context(of: lines, at: i),
                path: path,
                page: page,
                isRecognised: isRecognised,
                confidence: .uncertain
            )
        }

        guard let term else { return nil }

        return SlideDefinition(
            term: term,
            definition: definition,
            source: .colon,
            context: context(of: lines, at: i),
            path: path,
            page: page,
            isRecognised: isRecognised,
            confidence: confidence(term: term, definition: definition, isRecognised: isRecognised, vocabulary: vocabulary)
        )
    }

    /// A definition written as a sentence rather than with a colon. Two shapes,
    /// both high-signal:
    ///
    /// - **naming** — "… is called X", "… known as X", "… termed X": the term
    ///   is the short phrase *after* the marker.
    /// - **subject** — "X is defined as …", "X refers to …", and the cautious
    ///   copula "X is a/an …": the term is the phrase *before* the marker.
    ///
    /// The whole line is the definition; the model gets the surrounding lines
    /// as context, exactly as for the colon pass, so it can assemble and judge.
    /// The copula is the noisy one, so it only fires when the subject is a term
    /// the slides already use elsewhere (in `vocabulary`).
    private static func sentenceCandidate(
        lines: [String], at i: Int, path: String, page: Int, isRecognised: Bool, vocabulary: Set<String>
    ) -> SlideDefinition? {
        let line = lines[i]
        guard line.count >= 25, line.contains(" ") else { return nil }

        var term: String?

        // The marker is matched on the line itself, case-insensitively, so the
        // range it returns indexes straight into `line`. (Matching on a
        // lowercased copy and mapping the offset back crashes: lowercasing can
        // change the character count — Turkish "İ" → "i̇" — so the offset
        // overran the line.)

        // Naming markers: the thing being named follows the marker.
        for marker in Self.namingMarkers {
            guard let range = line.range(of: marker, options: .caseInsensitive) else { continue }
            term = namedTerm(String(line[range.upperBound...]))
            if term != nil { break }
        }

        // Subject markers: the term is what the sentence is about, before the
        // marker.
        if term == nil {
            for marker in Self.subjectMarkers {
                guard let range = line.range(of: marker, options: .caseInsensitive) else { continue }
                term = subjectTerm(String(line[line.startIndex..<range.lowerBound]), vocabulary: vocabulary, requireKnown: Self.copulaMarkers.contains(marker))
                if term != nil { break }
            }
        }

        guard let term, let definition = plausibleDefinition(line) else { return nil }

        return SlideDefinition(
            term: term,
            definition: definition,
            source: .sentence,
            context: context(of: lines, at: i),
            path: path,
            page: page,
            isRecognised: isRecognised,
            // A sentence match is a weaker signal than a colon, so it starts
            // uncertain and leans on the model to confirm.
            confidence: .uncertain
        )
    }

    /// Markers after which the named term appears ("… is called X").
    private static let namingMarkers: [String] = [
        " is called ", " are called ", " also called ", " is known as ",
        " are known as ", " also known as ", " is termed ", " are termed ",
        " referred to as ",
    ]

    /// Markers whose subject (before the marker) is the term. The plain plural
    /// copula " are " is left out on purpose: it fires on almost any sentence
    /// about a plural noun ("proteins are amphiphilic") and buried the real
    /// definitions under noise. " is a "/" is an " survive because they are
    /// gated to a known term below.
    private static let subjectMarkers: [String] = [
        " is defined as ", " are defined as ", " is described as ",
        " refers to ", " refer to ", " is a ", " is an ",
    ]

    /// The subset of `subjectMarkers` that is the plain copula — common and
    /// mostly not definitional, so it fires only for a known slide term.
    private static let copulaMarkers: Set<String> = [" is a ", " is an "]

    /// Function words that are never the head of a term, so a candidate that
    /// begins or ends on one is a sentence fragment, not a term.
    private static let functionWords: Set<String> = [
        "the", "a", "an", "of", "and", "or", "to", "in", "on", "as", "is",
        "are", "was", "were", "be", "been", "that", "which", "this", "these",
        "those", "there", "it", "they", "with", "by", "for", "used", "its",
    ]

    /// The words naming the term, taken from just after a naming marker: up to
    /// four, stopped at the first clause break, with trailing function words
    /// ("axis of" → "axis", "transverse diffusion and" → "transverse
    /// diffusion") pared off so the term does not trail into the sentence.
    private static func namedTerm(_ raw: String) -> String? {
        let head = raw.prefix { ![",", ".", ";", "(", ":"].contains($0) }
        var words = Array(head.split(separator: " ").prefix(5)).map(String.init)
        while let first = words.first, functionWords.contains(first.lowercased()) {
            words.removeFirst()
        }
        words = Array(words.prefix(4))
        while let last = words.last, functionWords.contains(last.lowercased()) {
            words.removeLast()
        }
        guard !words.isEmpty else { return nil }
        return plausibleTerm(words.joined(separator: " "))
    }

    /// The subject phrase before a subject marker: the last few words, with a
    /// leading article dropped. For the plain copula it must be a term the
    /// slides already use, so stray "This is a…" sentences do not slip in; and
    /// a subject that begins on a function word is a fragment, not a term.
    private static func subjectTerm(_ raw: String, vocabulary: Set<String>, requireKnown: Bool) -> String? {
        let words = raw.split(separator: " ")
        guard (1...5).contains(words.count) else { return nil }
        if let first = words.first, functionWords.contains(first.lowercased()) { return nil }
        guard let term = plausibleTerm(words.joined(separator: " ")) else { return nil }
        if requireKnown, !vocabulary.contains(SearchText.fold(term)) { return nil }
        return term
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
        var term = raw.trimmingCharacters(in: CharacterSet(charactersIn: " -•·*▪‣\t"))
        // A leading list marker ("a) ", "1) ", "iv. ") is the slide numbering
        // the term, not part of it ("c) Holocrine secretion" → "Holocrine
        // secretion"). A bare letter with no "./)" ("A band", "I band") is left
        // alone, so the ")"/"." is required.
        term = stripListMarker(term)
        // A lone "o" is these slides' bullet glyph ("o Cyclin…"); drop it so the
        // term is the word itself, not the bullet plus the word.
        if term.hasPrefix("o "), term.dropFirst(2).first?.isUppercase == true {
            term = String(term.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        // A lowercase leading article is noise ("the mitochondrion" →
        // "mitochondrion"). Only lowercase, so anatomy's "A band" / "I band"
        // keep their capital letter.
        for article in ["the ", "a ", "an "] where term.hasPrefix(article) {
            term = String(term.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        // Trim stray edge punctuation, then a lone unbalanced parenthesis the
        // pattern caught at the start or end — a balanced "(Cdk)" is left be.
        term = term.trimmingCharacters(in: CharacterSet(charactersIn: " -•·*▪‣\t.,;"))
        if term.hasPrefix("("), !term.contains(")") { term.removeFirst() }
        if term.hasSuffix(")"), !term.contains("(") { term.removeLast() }
        term = term.trimmingCharacters(in: .whitespaces)
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
        // Multi-word all-caps heads are slide titles ("CELL MEMBRANE
        // COMPONENTS"), not terms. Short acronyms are one word, so they pass.
        if words.count >= 2, term == term.uppercased(with: L.locale) { return nil }

        return term
    }

    /// Drops a leading list marker — a letter, a one/two-digit number, or a
    /// small roman numeral, followed by ")" or "." and a space.
    static func stripListMarker(_ term: String) -> String {
        guard let range = term.range(
            of: #"^\s*([A-Za-z]|\d{1,2}|[ivxIVX]{1,3})[\)\.]\s+"#,
            options: .regularExpression
        ) else { return term }
        return String(term[range.upperBound...]).trimmingCharacters(in: .whitespaces)
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

        // A definition that is really a web address is a citation, not an
        // explanation.
        let low = definition.lowercased()
        if low.contains("http") || low.contains("www.") { return nil }

        return definition
    }

    /// True when a label block's body reads as running prose worth handing to
    /// the model — not a bulleted list and not a formula. The model, not this
    /// check, decides whether a term is actually defined; here we only keep it
    /// from wasting a call on an obvious list or equation.
    private static func bodyIsProse(_ body: String) -> Bool {
        if body.filter({ "•▪‣".contains($0) }).count >= 2 { return false }
        guard body.split(separator: " ").count >= 4 else { return false }
        guard body.filter(\.isLetter).count >= body.count / 2 else { return false }
        return true
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
