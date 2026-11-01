import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device model's work over the heuristic definition candidates: it
/// decides which are real definitions, tidies them, and — when the first pass
/// is done — goes back over the ones it rejected and says *why*, so the misses
/// become a short, sorted pile for you to pick back rather than silent losses.
///
/// The pattern matcher cannot tell `Metacentric: The centromere is in the
/// middle…` (a definition) from `Topic: Epithelial Tissue 2…` (a title) — both
/// are "term: text", and the difference is meaning, not shape. So the matcher
/// casts a wide net and the model is the sieve, handed the **slide lines around
/// each candidate** so it can assemble a whole definition the pattern cut short.
///
/// Because the model is local and free, it keeps working while the app sits
/// idle: first judging, then classifying its own rejects. What it cannot be is
/// the final word — so your own marks (hide a bad one, keep a good one it
/// rejected) are kept in a file of their own that a re-review never wipes.
@MainActor
@Observable
final class GlossaryModel {
    /// What the model decided about one candidate.
    struct Verdict: Codable, Sendable {
        var accepted: Bool
        var term: String
        var definition: String

        /// For a rejected candidate: one word for why, filled by the later
        /// classification pass. `nil` until then. See `Rejection`.
        var reason: String?
    }

    /// The buckets the classification pass sorts rejects into. `incomplete` is
    /// the one worth your eye — a real definition cut short — so it reads
    /// first.
    enum Rejection: String, CaseIterable {
        case incomplete
        case list
        case title
        case person
        case citation
        case other

        init(keyword: String) {
            self = Rejection(rawValue: keyword.lowercased()) ?? .other
        }
    }

    private struct Cache: Codable, Sendable {
        /// Bumped when the prompt changes, so old verdicts are discarded and
        /// the candidates are judged again. 2 kept the term verbatim; 3 feeds
        /// the model the surrounding slide lines; 4 added rejection reasons;
        /// 5 keeps the candidate's clean term (the model's term is discarded)
        /// and drops citation/all-caps-title candidates at extraction; 6 lets
        /// the model extract the term itself for sentence candidates (with a
        /// "term appears in the passage" guard), instead of confirming a regex
        /// guess; 7 names the term after "is called …" (not the subject),
        /// strips the "… is called <term>" tail from the definition, and
        /// rejects fragment definitions.
        var version = 7
        var verdicts: [String: Verdict] = [:]
    }

    /// Your own decisions. Kept apart from the verdict cache and never tied to
    /// its version, so re-reviewing the slides never throws your curation away.
    private struct Marks: Codable, Sendable {
        var hidden: [String] = []
        var kept: [String] = []
    }

    /// Small on purpose: with each item carrying its slide lines, a bigger
    /// batch makes a long prompt the small model handles less reliably.
    private static let batchSize = 5

    private var verdicts: [String: Verdict] = [:]

    private var hiddenIDs: Set<String> = []
    private var keptIDs: Set<String> = []

    private(set) var isReviewing = false
    private(set) var isClassifying = false
    private(set) var reviewedCount = 0
    private(set) var pendingCount = 0

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private nonisolated static var cacheURL: URL {
        indexDirectory.appending(path: "definitions.json")
    }

    private nonisolated static var marksURL: URL {
        indexDirectory.appending(path: "glossary-marks.json")
    }

    private nonisolated static var indexDirectory: URL {
        StoreLocation.directory.appending(path: "Index", directoryHint: .isDirectory)
    }

    init() {
        verdicts = Self.read()?.verdicts ?? [:]
        let marks = Self.readMarks() ?? Marks()
        hiddenIDs = Set(marks.hidden)
        keptIDs = Set(marks.kept)
    }

    // MARK: Queries

    func verdict(for id: String) -> Verdict? { verdicts[id] }

    func isHidden(_ id: String) -> Bool { hiddenIDs.contains(id) }
    func isKept(_ id: String) -> Bool { keptIDs.contains(id) }

    // MARK: Your marks

    /// Hide a definition you do not want (or clear that). Hiding also clears a
    /// previous "keep", since the two are opposites.
    func setHidden(_ id: String, _ hidden: Bool) {
        if hidden {
            hiddenIDs.insert(id)
            keptIDs.remove(id)
        } else {
            hiddenIDs.remove(id)
        }
        saveMarks()
    }

    /// Keep a candidate the model rejected (or clear that). Keeping also clears
    /// a previous "hide".
    func setKept(_ id: String, _ kept: Bool) {
        if kept {
            keptIDs.insert(id)
            hiddenIDs.remove(id)
        } else {
            keptIDs.remove(id)
        }
        saveMarks()
    }

    private func saveMarks() {
        Self.writeMarks(Marks(hidden: Array(hiddenIDs), kept: Array(keptIDs)))
    }

    // MARK: Reviewing

    /// Judges every candidate not already judged, then classifies the rejects.
    /// Safe to call whenever the candidate list changes; it only works on what
    /// is new.
    func review(_ candidates: [SlideDefinition]) {
        guard isAvailable, !isReviewing else { return }

        let todo = candidates.filter { verdicts[$0.id] == nil }
        guard !todo.isEmpty else { return }

        isReviewing = true
        Task { await run(todo) }
    }

    private func run(_ todo: [SlideDefinition]) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            var working = verdicts

            // Phase one: is each candidate a definition? A colon candidate is
            // confirmed on its given term; a sentence candidate's term is a
            // regex guess, so the model extracts the real term itself.
            pendingCount = todo.count
            reviewedCount = 0

            for source in [SlideDefinition.Source.colon, .sentence] {
                let group = todo.filter { $0.source == source }
                var start = 0
                while start < group.count {
                    let batch = Array(group[start ..< min(start + Self.batchSize, group.count)])
                    let verdicts = source == .colon ? await judge(batch) : await extract(batch)
                    for (id, verdict) in verdicts { working[id] = verdict }
                    reviewedCount += batch.count
                    self.verdicts = working
                    if reviewedCount % 40 == 0 { Self.write(Cache(verdicts: working)) }
                    start += Self.batchSize
                }
            }
            Self.write(Cache(verdicts: working))

            // Phase two: why were the rejects rejected?
            let rejects = todo.filter { working[$0.id]?.accepted == false && working[$0.id]?.reason == nil }
            if !rejects.isEmpty {
                isClassifying = true
                pendingCount = rejects.count
                reviewedCount = 0
                var start = 0
                while start < rejects.count {
                    let batch = Array(rejects[start ..< min(start + Self.batchSize, rejects.count)])
                    let reasons = await classify(batch)
                    for candidate in batch {
                        working[candidate.id]?.reason = (reasons[candidate.id] ?? .other).rawValue
                    }
                    reviewedCount += batch.count
                    verdicts = working
                    if reviewedCount % 40 == 0 { Self.write(Cache(verdicts: working)) }
                    start += Self.batchSize
                }
                Self.write(Cache(verdicts: working))
                isClassifying = false
            }
        }
        #endif

        isReviewing = false
    }

    // MARK: Model — judging

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func judge(_ batch: [SlideDefinition]) async -> [String: Verdict] {
        var result: [String: Verdict] = [:]

        do {
            let session = LanguageModelSession(instructions: Self.judgeInstructions)
            let answer = try await session.respond(to: Self.batchPrompt(batch)).content
            result = Self.parseJudged(answer, batch: batch)
        } catch {
            // Whole-batch failure falls through to the per-item path below.
        }

        for candidate in batch where result[candidate.id] == nil {
            result[candidate.id] = await judgeOne(candidate)
        }

        return result
    }

    @available(macOS 26, *)
    private func judgeOne(_ candidate: SlideDefinition) async -> Verdict {
        do {
            let session = LanguageModelSession(instructions: Self.judgeInstructions)
            let answer = try await session.respond(to: Self.prompt(candidate)).content
            return Self.parseJudgedLine(Self.firstLine(answer), fallback: candidate)
        } catch {
            return Verdict(accepted: candidate.confidence == .high, term: candidate.term, definition: candidate.definition, reason: nil)
        }
    }

    // MARK: Model — extracting (sentence candidates)

    /// For a sentence candidate the regex term is a throwaway, so the model is
    /// handed only the passage and asked to name the term *and* its definition
    /// itself. This is what stops the "binding"/"environment" fragments: the
    /// model is no longer led by a wrong term to confirm.
    @available(macOS 26, *)
    private func extract(_ batch: [SlideDefinition]) async -> [String: Verdict] {
        var result: [String: Verdict] = [:]

        do {
            let session = LanguageModelSession(instructions: Self.extractInstructions)
            let answer = try await session.respond(to: Self.passageBatchPrompt(batch)).content
            result = Self.parseExtracted(answer, batch: batch)
        } catch {
            // Whole-batch failure falls through to the per-item path below.
        }

        for candidate in batch where result[candidate.id] == nil {
            result[candidate.id] = await extractOne(candidate)
        }

        return result
    }

    @available(macOS 26, *)
    private func extractOne(_ candidate: SlideDefinition) async -> Verdict {
        do {
            let session = LanguageModelSession(instructions: Self.extractInstructions)
            let answer = try await session.respond(to: Self.passagePrompt(candidate)).content
            return Self.parseExtractedLine(Self.firstLine(answer), fallback: candidate)
        } catch {
            // A sentence candidate the model never reached stays out: its regex
            // term is not trustworthy enough to accept on its own.
            return Verdict(accepted: false, term: candidate.term, definition: candidate.definition, reason: nil)
        }
    }

    // MARK: Model — classifying rejects

    @available(macOS 26, *)
    private func classify(_ batch: [SlideDefinition]) async -> [String: Rejection] {
        var result: [String: Rejection] = [:]

        do {
            let session = LanguageModelSession(instructions: Self.classifyInstructions)
            let answer = try await session.respond(to: Self.batchPrompt(batch)).content
            result = Self.parseClassified(answer, batch: batch)
        } catch {
            // fall through to per-item
        }

        for candidate in batch where result[candidate.id] == nil {
            result[candidate.id] = await classifyOne(candidate)
        }

        return result
    }

    @available(macOS 26, *)
    private func classifyOne(_ candidate: SlideDefinition) async -> Rejection {
        do {
            let session = LanguageModelSession(instructions: Self.classifyInstructions)
            let answer = try await session.respond(to: Self.prompt(candidate)).content
            return Rejection(keyword: Self.firstWord(Self.firstLine(answer)))
        } catch {
            return .other
        }
    }
    #endif

    // MARK: Prompts

    private static func prompt(_ candidate: SlideDefinition) -> String {
        "TERM: \(candidate.term)\nLINES:\n\(candidate.context)"
    }

    private static func batchPrompt(_ batch: [SlideDefinition]) -> String {
        batch.enumerated()
            .map { index, candidate in
                "ITEM \(index + 1)\nTERM: \(candidate.term)\nLINES:\n\(candidate.context)"
            }
            .joined(separator: "\n\n")
    }

    /// For extraction the model is given only the passage — no term, because
    /// finding the term is its job.
    private static func passagePrompt(_ candidate: SlideDefinition) -> String {
        "PASSAGE:\n\(candidate.context)"
    }

    private static func passageBatchPrompt(_ batch: [SlideDefinition]) -> String {
        batch.enumerated()
            .map { index, candidate in
                "ITEM \(index + 1)\nPASSAGE:\n\(candidate.context)"
            }
            .joined(separator: "\n\n")
    }

    private static let judgeInstructions = """
    You are given numbered items from medical lecture slides. Each has a TERM \
    and the LINES around it on the slide.

    For each item, reply on its own line starting with the item number and a \
    ')'. Then:

    - If the LINES define the TERM, write the term, then ' :: ', then the \
    definition, assembled from the LINES as one clean sentence. Keep the term \
    exactly as given — never generalise it or drop qualifiers. Fix obvious OCR \
    typos, but add NO facts, examples, numbers, or formulas beyond the LINES.
    - If the LINES do not define the term, write: NO

    Each line looks like `1) Term :: definition` or `2) NO`. One line per item, \
    in order, nothing else.
    """

    private static let extractInstructions = """
    You are given numbered passages from medical lecture slides.

    For each passage, reply on its own line starting with the item number and \
    a ')'. Then:

    - If the passage states the definition of a single term, write that term, \
    then ' :: ', then its definition. The term must be the exact word or \
    phrase the passage defines — a noun or noun phrase that actually appears in \
    the passage, not a whole sentence and not something you supply yourself. \
    When the passage says that something IS CALLED / IS KNOWN AS / IS TERMED / \
    IS REFERRED TO AS some name, that name is the term — never the subject in \
    front of it. Assemble the definition from the passage as one clean, \
    self-contained sentence, using ONLY what the passage says: add no facts, \
    numbers, examples, or formulas of your own, and never end it with "is \
    called …" or otherwise repeat the term. Fix obvious OCR typos only.
    - If the passage does not define a term, write: NO

    Each line looks like `1) Term :: definition` or `2) NO`. One line per item, \
    in order, nothing else.
    """

    private static let classifyInstructions = """
    You are given numbered items from medical lecture slides. Each has a TERM \
    and the LINES around it. None of them is a proper definition of its term. \
    For each, say in ONE word what it is instead:

    - incomplete — a real definition cut short, missing part of its explanation
    - list — a bare list of items or examples, not an explanation
    - title — a slide title or section heading
    - person — a person's name
    - citation — a reference, textbook, author, or URL
    - other — anything else

    Reply one line per item: the item number, ')', then the single word. \
    Example: `1) incomplete`. In order, nothing else.
    """

    // MARK: Parsing

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    private static func firstWord(_ line: String) -> String {
        line.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
    }

    /// Splits a numbered batch reply into (item number, remainder) pairs,
    /// leaving the `::` inside a verdict untouched.
    private static func numbered(_ answer: String, count: Int) -> [(index: Int, rest: String)] {
        var pairs: [(Int, String)] = []
        for raw in answer.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let digits = line.prefix { $0.isNumber }
            guard let number = Int(digits), (1...count).contains(number) else { continue }
            let rest = line.dropFirst(digits.count).drop { ").: ".contains($0) }
            pairs.append((number, String(rest)))
        }
        return pairs
    }

    static func parseJudged(_ answer: String, batch: [SlideDefinition]) -> [String: Verdict] {
        var result: [String: Verdict] = [:]
        for (number, rest) in numbered(answer, count: batch.count) {
            let candidate = batch[number - 1]
            result[candidate.id] = parseJudgedLine(rest, fallback: candidate)
        }
        return result
    }

    static func parseJudgedLine(_ line: String, fallback: SlideDefinition) -> Verdict {
        if let range = line.range(of: "::") {
            let definition = cleanDefinition(String(line[range.upperBound...]), term: fallback.term)

            if definition.count >= 15 {
                // The term is never the model's to rewrite. Left to it, it
                // echoes the slide's list numbering ("1) Cohesion"), repeats
                // the headword ("Neuron: Neuron: …"), or drags a trailing
                // colon along. The pattern matcher already handed us a clean
                // term, so keep that and take only the model's definition.
                return Verdict(accepted: true, term: fallback.term, definition: definition, reason: nil)
            }
        }

        if line.uppercased().hasPrefix("NO") {
            return Verdict(accepted: false, term: fallback.term, definition: fallback.definition, reason: nil)
        }

        return Verdict(accepted: fallback.confidence == .high, term: fallback.term, definition: fallback.definition, reason: nil)
    }

    static func parseExtracted(_ answer: String, batch: [SlideDefinition]) -> [String: Verdict] {
        var result: [String: Verdict] = [:]
        for (number, rest) in numbered(answer, count: batch.count) {
            result[batch[number - 1].id] = parseExtractedLine(rest, fallback: batch[number - 1])
        }
        return result
    }

    /// Here the term *is* the model's to choose — but only when it actually
    /// occurs in the passage, so it assembled it from the slide rather than
    /// inventing it. Anything else is rejected, fragment term and all.
    static func parseExtractedLine(_ line: String, fallback: SlideDefinition) -> Verdict {
        // Tolerate a stray leading "N)" on the per-item path, where `numbered`
        // has not already stripped it.
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.first?.isNumber == true {
            body = String(body.drop { $0.isNumber }.drop { ").: ".contains($0) })
        }

        if let range = body.range(of: "::") {
            let trim = CharacterSet(charactersIn: " -•·*\"'“”`")
            let term = String(body[..<range.lowerBound]).trimmingCharacters(in: trim)
            let definition = cleanDefinition(String(body[range.upperBound...]), term: term)

            if term.count >= 2, definition.count >= 15,
               isSelfContained(definition, term: term),
               termAppears(term, in: fallback.context) {
                return Verdict(accepted: true, term: term, definition: definition, reason: nil)
            }
        }

        return Verdict(accepted: false, term: fallback.term, definition: fallback.definition, reason: nil)
    }

    /// Words a definition never starts on: a relative or conjunction lead means
    /// the model handed back a clause torn out of its sentence ("that are mirror
    /// images of each other."), not a standalone explanation. Also rejects a
    /// definition of two or three words ("repeating units.") and one that just
    /// restates the term.
    private static let fragmentLeads: Set<String> = [
        "that", "which", "who", "whom", "whose", "and", "or", "but", "so",
        "because", "when", "while", "where", "as", "if", "then", "thus",
        "hence", "therefore", "of", "to",
    ]

    static func isSelfContained(_ definition: String, term: String) -> Bool {
        let words = definition.split(separator: " ")
        guard words.count >= 4 else { return false }
        if let first = words.first, fragmentLeads.contains(SearchText.fold(String(first))) {
            return false
        }
        return SearchText.fold(definition) != SearchText.fold(term)
    }

    /// True when the term's substantive words all occur in the passage — the
    /// guard that keeps the model from naming a term the slide never used.
    static func termAppears(_ term: String, in context: String) -> Bool {
        let haystack = SearchText.fold(context)
        let words = SearchText.fold(term).split(separator: " ").filter { $0.count >= 4 }
        if words.isEmpty {
            // A short term or acronym: require the whole thing to appear.
            return haystack.contains(SearchText.fold(term))
        }
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Tidies the model's definition: strips wrapping bullets/quotes and a
    /// leading "<term>:" the model copied from the slide, so the definition
    /// reads as its own sentence instead of repeating the headword.
    static func cleanDefinition(_ raw: String, term: String) -> String {
        let edge = CharacterSet(charactersIn: " -•·*▪‣:\"'“”`\t")
        var def = raw.trimmingCharacters(in: edge)

        if let colon = def.firstIndex(of: ":"),
           SearchText.fold(String(def[..<colon])) == SearchText.fold(term) {
            def = String(def[def.index(after: colon)...])
        }

        def = stripNamingTail(def, term: term)

        return def.trimmingCharacters(in: edge)
    }

    private static let namingTails: [String] = [
        " is called as ", " are called as ", " is called ", " are called ",
        " also called ", " is known as ", " are known as ", " also known as ",
        " is termed ", " are termed ", " is referred to as ",
        " are referred to as ", " referred to as ",
    ]

    /// Drops a trailing "… is called <term>" clause that merely restates the
    /// headword, so "solutions … are called buffer systems" collapses to the
    /// genus phrase "solutions …". Only fires when the clause actually names
    /// the term, so an unrelated "called upon" is left alone.
    static func stripNamingTail(_ definition: String, term: String) -> String {
        let foldedTerm = SearchText.fold(term)
        guard !foldedTerm.isEmpty else { return definition }

        var cut: String.Index?
        for marker in namingTails {
            guard let range = definition.range(of: marker, options: .caseInsensitive) else { continue }
            let tail = SearchText.fold(String(definition[range.upperBound...]))
            guard tail.contains(foldedTerm) else { continue }
            if cut == nil || range.lowerBound < cut! { cut = range.lowerBound }
        }
        guard let cut else { return definition }

        var head = String(definition[..<cut])
        // Drop a connector left dangling by the cut ("…another, and" → "…another").
        if let tail = head.range(of: #"[\s,;]+(and|or|which|that)$"#,
                                 options: [.regularExpression, .caseInsensitive]) {
            head = String(head[..<tail.lowerBound])
        }
        return head.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-•·*"))
    }

    static func parseClassified(_ answer: String, batch: [SlideDefinition]) -> [String: Rejection] {
        var result: [String: Rejection] = [:]
        for (number, rest) in numbered(answer, count: batch.count) {
            result[batch[number - 1].id] = Rejection(keyword: firstWord(rest))
        }
        return result
    }

    // MARK: Disk

    private nonisolated static func read() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == Cache().version
        else { return nil }
        return cache
    }

    private nonisolated static func write(_ cache: Cache) {
        write(cache, to: cacheURL, what: "sözlük incelemesi")
    }

    private nonisolated static func readMarks() -> Marks? {
        guard let data = try? Data(contentsOf: marksURL),
              let marks = try? JSONDecoder().decode(Marks.self, from: data)
        else { return nil }
        return marks
    }

    private nonisolated static func writeMarks(_ marks: Marks) {
        write(marks, to: marksURL, what: "sözlük işaretleri")
    }

    private nonisolated static func write<T: Encodable>(_ value: T, to url: URL, what: String) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("MED: \(what) yazılamadı — \(error)")
        }
    }
}
