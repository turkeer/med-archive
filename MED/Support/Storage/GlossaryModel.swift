import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The second pass over the heuristic definition candidates: the on-device
/// model decides which are real definitions and cleans up the wording.
///
/// This is where the glossary earns its keep. The pattern matcher cannot tell
/// `Metacentric: The centromere is in the middle…` (a definition) from
/// `Topic: Epithelial Tissue 2…` (a slide title) — both are "term: text", and
/// the difference is meaning, not shape. So the matcher casts a wide net and
/// the model is the sieve.
///
/// Each candidate is handed the **slide lines around it**, not just the one
/// line the colon sat on, so the model can assemble a whole definition that the
/// pattern cut short — and it is told, firmly, to build only from those lines
/// and keep the term verbatim. Judging a bare line instead made it reject real
/// but truncated definitions and, worse, pad or generalise the ones it kept.
///
/// Candidates go up several at a time (`batchSize`) to amortise the long
/// instruction over one call instead of re-reading it for every term; anything
/// a batch reply does not cleanly cover is re-judged on its own, so batching
/// only ever costs speed, never correctness.
///
/// Verdicts are cached on disk beside the slide index, so the pass runs once
/// and then only over whatever is new. Everything is optional: with no model
/// (`isAvailable == false`) the glossary falls back to the heuristic tiers and
/// this class simply never does anything.
@MainActor
@Observable
final class GlossaryModel {
    /// What the model decided about one candidate.
    struct Verdict: Codable, Sendable {
        var accepted: Bool
        var term: String
        var definition: String
    }

    private struct Cache: Codable, Sendable {
        /// Bumped when the prompt changes, so old verdicts are discarded and
        /// the candidates are judged again. 2 kept the term verbatim; 3 feeds
        /// the model the surrounding slide lines to assemble from.
        var version = 3
        var verdicts: [String: Verdict] = [:]
    }

    /// Small on purpose: with each item carrying its slide lines, a bigger
    /// batch makes a long prompt the small model handles less reliably.
    private static let batchSize = 5

    private var verdicts: [String: Verdict] = [:]

    private(set) var isReviewing = false
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
        StoreLocation.directory
            .appending(path: "Index", directoryHint: .isDirectory)
            .appending(path: "definitions.json")
    }

    init() {
        verdicts = Self.read()?.verdicts ?? [:]
    }

    /// The model's call on a candidate, or `nil` if it has not been looked at.
    func verdict(for id: String) -> Verdict? {
        verdicts[id]
    }

    // MARK: Reviewing

    /// Reviews every candidate not already judged, in the background. Safe to
    /// call whenever the candidate list changes; it only works on what is new.
    func review(_ candidates: [SlideDefinition]) {
        guard isAvailable, !isReviewing else { return }

        let todo = candidates.filter { verdicts[$0.id] == nil }
        guard !todo.isEmpty else { return }

        isReviewing = true
        pendingCount = todo.count
        reviewedCount = 0

        Task { await run(todo) }
    }

    private func run(_ todo: [SlideDefinition]) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            var working = verdicts
            var done = 0
            var start = 0

            while start < todo.count {
                let batch = Array(todo[start ..< min(start + Self.batchSize, todo.count)])
                let judged = await judge(batch)

                for (id, verdict) in judged { working[id] = verdict }
                done += batch.count
                reviewedCount = done
                verdicts = working                          // publish per batch

                if done % 40 == 0 { Self.write(Cache(verdicts: working)) }
                start += Self.batchSize
            }

            Self.write(Cache(verdicts: working))
        }
        #endif

        isReviewing = false
        pendingCount = 0
    }

    #if canImport(FoundationModels)
    /// Judges a batch in one call, then fills any item the reply did not
    /// cleanly cover by judging it on its own.
    @available(macOS 26, *)
    private func judge(_ batch: [SlideDefinition]) async -> [String: Verdict] {
        var result: [String: Verdict] = [:]

        do {
            let session = LanguageModelSession(instructions: Self.batchInstructions)
            let answer = try await session.respond(to: Self.batchPrompt(batch)).content
            result = Self.parseBatch(answer, batch: batch)
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
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: Self.prompt(candidate)).content
            return Self.parse(answer, fallback: candidate)
        } catch {
            return Verdict(
                accepted: candidate.confidence == .high,
                term: candidate.term,
                definition: candidate.definition
            )
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

    private static let instructions = """
    You are given a TERM and the LINES around it on a medical lecture slide.

    If the LINES define the term, reply with the term, then the separator \
    ' :: ', then the definition, assembled from the LINES as one clean \
    sentence. Keep the term exactly as given — do not generalise it, shorten \
    it, or drop qualifiers ("Strong acids" stays "Strong acids"). Fix obvious \
    OCR typos, but add NO facts, examples, numbers, or formulas that are not in \
    the LINES.

    If the LINES do not define the term — a title, a person's name, a citation \
    or textbook, lab materials, a bare list fragment, or anything that does not \
    explain the term — reply with exactly: NO

    Reply with a single line and nothing else.
    """

    private static let batchInstructions = """
    You are given several numbered items from medical lecture slides. Each item \
    has a TERM and the LINES around it on the slide.

    For each item, reply on its own line, starting with the item number and a \
    ')'. Then:

    - If the LINES define the TERM, write the term, then ' :: ', then the \
    definition, assembled from the LINES as one clean sentence. Keep the term \
    exactly as given — never generalise it or drop qualifiers. Fix obvious OCR \
    typos, but add NO facts, examples, numbers, or formulas beyond the LINES.
    - If the LINES do not define the term, write: NO

    So each line looks like `1) Term :: definition` or `2) NO`. Reply with \
    exactly one line per item, in order, and nothing else.
    """

    // MARK: Parsing

    /// Reads the model's one line. `term :: definition` is an acceptance; `NO`
    /// (or anything unparseable) leaves the candidate to its heuristic fate
    /// rather than inventing a verdict.
    static func parse(_ answer: String, fallback: SlideDefinition) -> Verdict {
        let line = answer
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""

        return verdict(fromLine: line, fallback: fallback)
    }

    /// Reads one numbered line per item (`1) term :: def`, `2) NO`). Items the
    /// reply skips or garbles are simply left out, for the caller to re-judge.
    static func parseBatch(_ answer: String, batch: [SlideDefinition]) -> [String: Verdict] {
        var result: [String: Verdict] = [:]

        for rawLine in answer.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            let digits = line.prefix { $0.isNumber }
            guard let number = Int(digits), (1...batch.count).contains(number) else { continue }

            // Drop the number and the separator that follows it, but not the
            // "::" inside the verdict.
            let rest = line
                .dropFirst(digits.count)
                .drop { ").: ".contains($0) }
            let candidate = batch[number - 1]

            result[candidate.id] = verdict(fromLine: String(rest), fallback: candidate)
        }

        return result
    }

    private static func verdict(fromLine line: String, fallback: SlideDefinition) -> Verdict {
        if let range = line.range(of: "::") {
            let trim = CharacterSet(charactersIn: " -•·*\"'“”`")
            let term = String(line[..<range.lowerBound]).trimmingCharacters(in: trim)
            let definition = String(line[range.upperBound...]).trimmingCharacters(in: trim)

            if term.count >= 2, definition.count >= 15 {
                return Verdict(accepted: true, term: term, definition: definition)
            }
        }

        if line.uppercased().hasPrefix("NO") {
            return Verdict(accepted: false, term: fallback.term, definition: fallback.definition)
        }

        // Unparseable: keep it only if the heuristic was already confident.
        return Verdict(
            accepted: fallback.confidence == .high,
            term: fallback.term,
            definition: fallback.definition
        )
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
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } catch {
            print("MED: sözlük incelemesi yazılamadı — \(error)")
        }
    }
}
