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

        /// Set once the slower third pass has re-checked an *accepted* entry
        /// against a stricter "is this really a whole definition?" bar. `nil`
        /// means not deep-checked yet, so that pass still owes it a look;
        /// `true` means it passed. A failed check flips `accepted` to false.
        /// Optional with a default, so an older cache decodes unverified and
        /// gets re-checked rather than being discarded.
        var verified: Bool? = nil
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

    /// What the strict third pass decided for one entry: keep it, or demote it
    /// with a reason. `nil` in a result means the model never answered, so the
    /// caller leaves the entry accepted (but stamps it checked).
    typealias VerifyOutcome = (keep: Bool, reason: Rejection?)

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
        /// rejects fragment definitions; 8 re-routes generic label heads
        /// ("Definition:", "Functions:") so the real term is extracted or the
        /// block dropped, evens out term casing, and rejects a definition left
        /// dangling on a copula ("… this group of proteins is"); 9 recognises
        /// a bulleted/numbered label head ("• Definition:"), routes any prose
        /// body (not just "X is Y") to extraction, and strips list lettering
        /// from the term ("b) Apocrine secretion" → "Apocrine secretion");
        /// 10 settles the sentence-extraction tier by consensus — several
        /// sampled passes, keeping only a term a majority agree on.
        var version = 10
        var verdicts: [String: Verdict] = [:]
    }

    /// One entry the model-driven pipeline produced for a page: the term it
    /// found, the definition it wrote, and the verdict the later stages reached.
    private struct ProducedEntry: Codable, Sendable {
        var term: String
        var definition: String
        var accepted: Bool
        var reason: String?
    }

    /// One slide page's extraction state: which page it is, a fingerprint of
    /// the page text (so an unchanged page is skipped and a changed one re-reads
    /// itself), the highest stage finished (0…4), and the entries so far.
    /// Persisted, so the long whole-archive read is resumable across launches.
    private struct PageRecord: Codable, Sendable {
        var path: String
        var page: Int
        var fingerprint: Int
        var stage: Int
        var entries: [ProducedEntry]
    }

    private struct PageCache: Codable, Sendable {
        /// Bumped when the pipeline's prompts or stages change shape, so stale
        /// page records are dropped and the pages are read again.
        var version = 1
        var pages: [String: PageRecord] = [:]
    }

    /// The polish pass's confirmed term-pair decisions. Kept in its own file so
    /// re-reading the slides never throws them away.
    private struct AliasCache: Codable, Sendable {
        var version = 1
        var links: [String: Bool] = [:]
    }

    /// Your own decisions. Kept apart from the verdict cache and never tied to
    /// its version, so re-reviewing the slides never throws your curation away.
    private struct Marks: Codable, Sendable {
        var hidden: [String] = []
        var kept: [String] = []
        /// Crossover points you dismissed, by `CommitteeIntersection.Point.id`.
        /// A newly added optional field, so an older marks file decodes with it
        /// empty.
        var hiddenCrossovers: [String]? = nil
    }

    /// Small on purpose: with each item carrying its slide lines, a bigger
    /// batch makes a long prompt the small model handles less reliably.
    private static let batchSize = 5

    /// Consensus over the sentence-extraction tier: each passage is extracted
    /// `consensusPasses` times with sampling (`consensusTemperature`), and a
    /// term is accepted only if at least `consensusQuorum` of those passes land
    /// on it. Three passes with a quorum of two is the usual majority vote.
    private static let consensusPasses = 3
    private static let consensusQuorum = 2
    private static let consensusTemperature = 0.7

    private var verdicts: [String: Verdict] = [:]

    /// The model-driven pipeline's per-page state, keyed by "path#page".
    private var pageRecords: [String: PageRecord] = [:]

    /// The candidates the model produced by reading the pages, rebuilt from
    /// `pageRecords`. When the on-device model is available these replace the
    /// regex candidates as the glossary's source — the view reads them exactly
    /// as it read the regex ones, with `verdicts` filled in alongside for the
    /// ones that reached the final stage.
    private(set) var candidates: [SlideDefinition] = []

    /// The polish pass's confirmed decisions, keyed by a sorted "foldA|foldB"
    /// term pair → whether the model judged the two the same term (one the
    /// plural or a spelling variant of the other). Persisted so a pair is never
    /// re-asked.
    private var termLinks: [String: Bool] = [:]

    /// Derived from the confirmed-true links: each folded term → the canonical
    /// key of its equivalence class, so the view groups "action potential" and
    /// "action potentials" under one heading. A term with no link maps to
    /// itself (left out here), so the lookup falls back to the term's own fold.
    private(set) var termAliases: [String: String] = [:]

    private var hiddenIDs: Set<String> = []
    private var keptIDs: Set<String> = []
    private var hiddenCrossoverIDs: Set<String> = []

    private(set) var isReviewing = false
    private(set) var isClassifying = false
    /// The third pass: re-checking already-accepted entries against a stricter
    /// definition bar. Runs while `isReviewing` is still true.
    private(set) var isVerifying = false
    /// The model-driven whole-page read is running. Also runs under
    /// `isReviewing`, so the existing progress row shows it.
    private(set) var isBuilding = false
    /// The polish pass is running: confirming singular/plural term pairs. Also
    /// under `isReviewing`, and it follows the page read.
    private(set) var isLinking = false
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

    private nonisolated static var pagesURL: URL {
        indexDirectory.appending(path: "glossary-pages.json")
    }

    private nonisolated static var aliasesURL: URL {
        indexDirectory.appending(path: "glossary-aliases.json")
    }

    private nonisolated static var indexDirectory: URL {
        StoreLocation.directory.appending(path: "Index", directoryHint: .isDirectory)
    }

    init() {
        verdicts = Self.read()?.verdicts ?? [:]
        let marks = Self.readMarks() ?? Marks()
        hiddenIDs = Set(marks.hidden)
        keptIDs = Set(marks.kept)
        hiddenCrossoverIDs = Set(marks.hiddenCrossovers ?? [])
        pageRecords = Self.readPages()?.pages ?? [:]
        termLinks = Self.readAliases()?.links ?? [:]
        rebuildFromPages()
        rebuildAliases()
    }

    // MARK: Queries

    func verdict(for id: String) -> Verdict? { verdicts[id] }

    func isHidden(_ id: String) -> Bool { hiddenIDs.contains(id) }
    func isKept(_ id: String) -> Bool { keptIDs.contains(id) }

    /// Whether a crossover point was dismissed. The crossover view filters on
    /// this so the residual noise can be pruned by hand as the glossary grows.
    func isCrossoverHidden(_ id: String) -> Bool { hiddenCrossoverIDs.contains(id) }

    var hasHiddenCrossovers: Bool { !hiddenCrossoverIDs.isEmpty }

    /// One term the clean glossary shows, with where it came from. The id is
    /// dropped — a feature built on these cares about the term and its slide,
    /// not the candidate's bookkeeping key.
    struct CuratedTerm {
        let term: String
        let path: String
        let page: Int
    }

    /// The definitions the clean glossary would show: accepted by the model
    /// (or high-confidence when there is no model), plus the ones you kept,
    /// minus the ones you hid. The uncertain / unreviewed tiers are left out on
    /// purpose — this is the curated set other features build on, so it stays
    /// clean. Mirrors `GlossaryView.shownEntries`, without its display toggle.
    ///
    /// Lives here, beside the verdicts and marks it reads, so the committee
    /// intersections (and anything later) share one definition of "the glossary"
    /// rather than each re-deriving it and drifting apart.
    func curatedTerms(from candidates: [SlideDefinition]) -> [CuratedTerm] {
        var items: [CuratedTerm] = []
        for candidate in candidates {
            if isKept(candidate.id) {
                let verdict = verdict(for: candidate.id)
                items.append(CuratedTerm(term: verdict?.term ?? candidate.term,
                                         path: candidate.path, page: candidate.page))
                continue
            }
            if isHidden(candidate.id) { continue }

            if isAvailable {
                // With a model, only what it confirmed counts. Unreviewed and
                // rejected candidates stay out so the set does not fill with noise.
                if let verdict = verdict(for: candidate.id), verdict.accepted {
                    items.append(CuratedTerm(term: verdict.term,
                                             path: candidate.path, page: candidate.page))
                }
            } else if candidate.confidence == .high {
                // No model: fall back to the heuristic's high-confidence tier.
                items.append(CuratedTerm(term: candidate.term,
                                         path: candidate.path, page: candidate.page))
            }
        }
        return items
    }

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

    /// Dismiss a crossover point (or bring it back). Keyed by the point's id,
    /// which is stable across rebuilds (same committee + term), so the choice
    /// survives the slides being re-read.
    func setCrossoverHidden(_ id: String, _ hidden: Bool) {
        if hidden {
            hiddenCrossoverIDs.insert(id)
        } else {
            hiddenCrossoverIDs.remove(id)
        }
        saveMarks()
    }

    private func saveMarks() {
        Self.writeMarks(Marks(hidden: Array(hiddenIDs), kept: Array(keptIDs),
                              hiddenCrossovers: Array(hiddenCrossoverIDs)))
    }

    // MARK: Reviewing

    /// Judges every candidate not already judged, then classifies the rejects.
    /// Safe to call whenever the candidate list changes; it only works on what
    /// is new.
    func review(_ candidates: [SlideDefinition]) {
        guard isAvailable, !isReviewing else { return }

        let todo = candidates.filter { verdicts[$0.id] == nil }
        // Accepted entries the slower third pass has not deep-checked yet —
        // including ones accepted on earlier launches, so the stricter bar is
        // applied retroactively to a glossary built before it existed.
        let needsDeepCheck = candidates.contains {
            guard let verdict = verdicts[$0.id] else { return false }
            return verdict.accepted && verdict.verified != true
        }
        guard !todo.isEmpty || needsDeepCheck else { return }

        isReviewing = true
        Task { await run(todo, all: candidates) }
    }

    private func run(_ todo: [SlideDefinition], all: [SlideDefinition]) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            var working = verdicts

            if !todo.isEmpty {
                // Phase one: is each candidate a definition? A colon candidate
                // is confirmed on its given term; a sentence candidate's term
                // is a regex guess, so the model extracts the real term itself.
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

            // Phase three: the slow background pass. Every accepted entry not
            // yet deep-checked is re-judged against a stricter "is this really
            // a whole definition?" bar, by majority vote so a lone stray "no"
            // never drops a good one. A failure is demoted to the review pile
            // with a reason; a pass is stamped so it is never re-checked. This
            // is what quietly cleans a glossary of titles and half-sentences
            // the first pass let through, a few at a time, across launches.
            let toVerify = all.filter { candidate in
                guard let verdict = working[candidate.id] else { return false }
                return verdict.accepted && verdict.verified != true
            }
            if !toVerify.isEmpty {
                isVerifying = true
                pendingCount = toVerify.count
                reviewedCount = 0
                var start = 0
                while start < toVerify.count {
                    let batch = Array(toVerify[start ..< min(start + Self.batchSize, toVerify.count)])
                    let pairs = batch.compactMap { candidate -> (SlideDefinition, Verdict)? in
                        working[candidate.id].map { (candidate, $0) }
                    }
                    let outcomes = await verify(pairs)
                    for (candidate, verdict) in pairs {
                        switch outcomes[candidate.id] {
                        case .some(let outcome) where !outcome.keep:
                            working[candidate.id] = Verdict(
                                accepted: false, term: verdict.term, definition: verdict.definition,
                                reason: (outcome.reason ?? .other).rawValue, verified: true)
                        default:
                            // Kept, or the model never answered: stamp it so the
                            // pass does not keep coming back to the same entry.
                            working[candidate.id]?.verified = true
                        }
                    }
                    reviewedCount += batch.count
                    verdicts = working
                    if reviewedCount % 40 == 0 { Self.write(Cache(verdicts: working)) }
                    start += Self.batchSize
                }
                Self.write(Cache(verdicts: working))
                isVerifying = false
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
        // Consensus. The passage is extracted several times with sampling on,
        // and only a term that recurs across a majority of passes is kept. An
        // invented or unstable term changes from one pass to the next and never
        // reaches the quorum, so this is what filters the random mis-extractions
        // a single greedy pass lets through — the term the slide really defines
        // is the one the model keeps landing on.
        var ballots: [String: [Verdict]] = [:]
        for _ in 0 ..< Self.consensusPasses {
            let pass = await extractPass(batch, temperature: Self.consensusTemperature)
            for (id, verdict) in pass where verdict.accepted {
                ballots[id, default: []].append(verdict)
            }
        }

        var result: [String: Verdict] = [:]
        for candidate in batch {
            result[candidate.id] = Self.consensus(of: ballots[candidate.id] ?? [], fallback: candidate)
        }
        return result
    }

    /// One extraction pass over the batch, falling back to the per-item path
    /// for any item the batch reply skipped.
    @available(macOS 26, *)
    private func extractPass(_ batch: [SlideDefinition], temperature: Double) async -> [String: Verdict] {
        var result: [String: Verdict] = [:]
        let options = GenerationOptions(temperature: temperature)

        do {
            let session = LanguageModelSession(instructions: Self.extractInstructions)
            let answer = try await session.respond(to: Self.passageBatchPrompt(batch), options: options).content
            result = Self.parseExtracted(answer, batch: batch)
        } catch {
            // Whole-batch failure falls through to the per-item path below.
        }

        for candidate in batch where result[candidate.id] == nil {
            result[candidate.id] = await extractOne(candidate, options: options)
        }

        return result
    }

    @available(macOS 26, *)
    private func extractOne(_ candidate: SlideDefinition, options: GenerationOptions) async -> Verdict {
        do {
            let session = LanguageModelSession(instructions: Self.extractInstructions)
            let answer = try await session.respond(to: Self.passagePrompt(candidate), options: options).content
            return Self.parseExtractedLine(Self.firstLine(answer), fallback: candidate)
        } catch {
            // A sentence candidate the model never reached stays out: its regex
            // term is not trustworthy enough to accept on its own.
            return Verdict(accepted: false, term: candidate.term, definition: candidate.definition, reason: nil)
        }
    }

    /// Settles the passes' votes for one candidate: the term the most passes
    /// agreed on wins, and it must clear the quorum on its own, or the
    /// candidate is dropped. The fullest definition among the agreeing passes
    /// is the one kept.
    static func consensus(of ballots: [Verdict], fallback: SlideDefinition) -> Verdict {
        let rejected = Verdict(accepted: false, term: fallback.term, definition: fallback.definition, reason: nil)
        guard ballots.count >= consensusQuorum else { return rejected }

        let byTerm = Dictionary(grouping: ballots) { SearchText.fold($0.term) }
        guard let winners = byTerm.values.max(by: { $0.count < $1.count }),
              winners.count >= consensusQuorum,
              let best = winners.max(by: { $0.definition.count < $1.definition.count })
        else { return rejected }

        return Verdict(accepted: true, term: best.term, definition: best.definition, reason: nil)
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

    // MARK: Model — deep verification (phase three)

    /// Re-judges a batch of accepted entries by majority vote: each is checked
    /// over several sampled passes, and demoted only when a quorum of them
    /// agree it is not a definition. Keeping on a tie is deliberate — the bar
    /// to *remove* something the glossary already shows is higher than the bar
    /// to let it in.
    @available(macOS 26, *)
    private func verify(_ pairs: [(SlideDefinition, Verdict)]) async -> [String: VerifyOutcome] {
        var noVotes: [String: Int] = [:]
        var answered: Set<String> = []
        var reasons: [String: Rejection] = [:]

        for _ in 0 ..< Self.consensusPasses {
            let pass = await verifyPass(pairs, temperature: Self.consensusTemperature)
            for (id, outcome) in pass {
                answered.insert(id)
                if !outcome.keep {
                    noVotes[id, default: 0] += 1
                    if reasons[id] == nil, let reason = outcome.reason { reasons[id] = reason }
                }
            }
        }

        var result: [String: VerifyOutcome] = [:]
        for (candidate, _) in pairs where answered.contains(candidate.id) {
            if (noVotes[candidate.id] ?? 0) >= Self.consensusQuorum {
                result[candidate.id] = (keep: false, reason: reasons[candidate.id] ?? .other)
            } else {
                result[candidate.id] = (keep: true, reason: nil)
            }
        }
        return result
    }

    @available(macOS 26, *)
    private func verifyPass(_ pairs: [(SlideDefinition, Verdict)], temperature: Double) async -> [String: VerifyOutcome] {
        var result: [String: VerifyOutcome] = [:]
        let options = GenerationOptions(temperature: temperature)

        do {
            let session = LanguageModelSession(instructions: Self.verifyInstructions)
            let answer = try await session.respond(to: Self.verifyBatchPrompt(pairs), options: options).content
            result = Self.parseVerified(answer, pairs: pairs)
        } catch {
            // Whole-batch failure falls through to the per-item path below.
        }

        for (candidate, verdict) in pairs where result[candidate.id] == nil {
            if let outcome = await verifyOne(candidate, verdict, options: options) {
                result[candidate.id] = outcome
            }
        }
        return result
    }

    @available(macOS 26, *)
    private func verifyOne(_ candidate: SlideDefinition, _ verdict: Verdict, options: GenerationOptions) async -> VerifyOutcome? {
        do {
            let session = LanguageModelSession(instructions: Self.verifyInstructions)
            let answer = try await session.respond(to: Self.verifyPrompt(candidate, verdict), options: options).content
            return Self.parseVerifiedLine(Self.firstLine(answer))
        } catch {
            return nil
        }
    }
    #endif

    // MARK: Model-driven glossary (whole-page reading)

    /// Reads every slide page with the model and builds the glossary the
    /// thorough way, in four small steps the small model can each do well:
    /// scan the page for defined terms, extract each definition, check it is a
    /// whole sentence, then put it to a majority-vote gate. Resumable: a page
    /// whose text is unchanged and already finished is skipped, so this picks
    /// up where the last launch left off and only new or changed pages cost
    /// anything. The first full run is long by design — that is the point.
    func buildGlossary(from pages: [SlideIndex.Page]) {
        guard isAvailable, !isReviewing else { return }
        let pageTodo = pages.filter { page in
            guard let record = pageRecords[page.id] else { return true }
            return record.fingerprint != Self.fingerprint(page.text) || record.stage < 4
        }
        // The polish pass also has work if the current terms have singular/plural
        // pairs no one has judged yet. So a launch with nothing new to read can
        // still run the (tiny) term-linking pass over the glossary it already has.
        let hasLinkWork = !pendingTermPairs().isEmpty
        guard !pageTodo.isEmpty || hasLinkWork else { return }

        isReviewing = true
        isBuilding = !pageTodo.isEmpty
        Task {
            if !pageTodo.isEmpty { await runExtraction(pageTodo) }
            await runLinking()
            isReviewing = false
        }
    }

    private func runExtraction(_ pages: [SlideIndex.Page]) async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            pendingCount = pages.count
            reviewedCount = 0

            for page in pages {
                let fingerprint = Self.fingerprint(page.text)
                var record = pageRecords[page.id]
                if record == nil || record!.fingerprint != fingerprint {
                    record = PageRecord(path: page.path, page: page.number,
                                        fingerprint: fingerprint, stage: 0, entries: [])
                }

                // Stage 1 — scan: which terms does this page actually define?
                if record!.stage < 1 {
                    let terms = await scanPage(page.text)
                    record!.entries = terms.map {
                        ProducedEntry(term: $0, definition: "", accepted: false, reason: nil)
                    }
                    record!.stage = 1
                }

                // Stage 2 — extract: the definition sentence for each term.
                if record!.stage < 2 {
                    for index in record!.entries.indices {
                        record!.entries[index].definition = await extractDefinition(
                            term: record!.entries[index].term, page: page.text) ?? ""
                    }
                    record!.entries.removeAll { $0.definition.isEmpty }
                    record!.stage = 2
                }

                // Stage 3 — sentence check: tidy it, or drop a non-sentence.
                if record!.stage < 3 {
                    for index in record!.entries.indices {
                        if let clean = await sentenceCheck(
                            term: record!.entries[index].term,
                            definition: record!.entries[index].definition) {
                            record!.entries[index].definition = clean
                        } else {
                            record!.entries[index].accepted = false
                            record!.entries[index].reason = Rejection.incomplete.rawValue
                        }
                    }
                    record!.stage = 3
                }

                // Stage 4 — gate: is each really a definition? Majority vote.
                if record!.stage < 4 {
                    for index in record!.entries.indices where record!.entries[index].reason == nil {
                        let outcome = await gate(
                            term: record!.entries[index].term,
                            definition: record!.entries[index].definition, page: page.text)
                        record!.entries[index].accepted = outcome.keep
                        if !outcome.keep {
                            record!.entries[index].reason = (outcome.reason ?? .other).rawValue
                        }
                    }
                    record!.stage = 4
                }

                pageRecords[page.id] = record
                reviewedCount += 1
                if reviewedCount % 10 == 0 {
                    rebuildFromPages()
                    Self.writePages(PageCache(pages: pageRecords))
                }
            }
            rebuildFromPages()
            Self.writePages(PageCache(pages: pageRecords))
        }
        #endif

        isBuilding = false
    }

    /// Rebuilds the model candidates (and the verdicts for the finished ones)
    /// from the saved page records, so a launch shows the glossary as it was
    /// without reading a thing. An entry carries a verdict only once its page
    /// reached the gate (stage 4); until then it is provisional and stays out.
    private func rebuildFromPages() {
        var produced: [SlideDefinition] = []
        for record in pageRecords.values {
            for entry in record.entries where !entry.definition.isEmpty {
                let candidate = SlideDefinition(
                    term: entry.term, definition: entry.definition, source: .colon,
                    context: "", path: record.path, page: record.page,
                    isRecognised: false, confidence: .high)
                produced.append(candidate)
                if record.stage >= 4 {
                    verdicts[candidate.id] = Verdict(
                        accepted: entry.accepted, term: entry.term,
                        definition: entry.definition, reason: entry.reason, verified: true)
                }
            }
        }
        candidates = produced.sorted {
            $0.term.localizedStandardCompare($1.term) == .orderedAscending
        }
    }

    // MARK: Polish pass — singular/plural term linking

    /// The canonical grouping key for a folded term: its equivalence-class
    /// representative when the model has linked it to a variant, else itself.
    /// The view groups on this so "action potential" and "action potentials"
    /// fall under one heading.
    func canonicalKey(for folded: String) -> String { termAliases[folded] ?? folded }

    /// The displayed terms, folded → a real spelling. Only what the glossary
    /// actually shows (accepted or kept, not hidden) is linked.
    private func displayedTermForms() -> [String: String] {
        var forms: [String: String] = [:]
        for candidate in candidates {
            guard !isHidden(candidate.id) else { continue }
            let shown = isKept(candidate.id) || (verdict(for: candidate.id)?.accepted ?? false)
            guard shown else { continue }
            let folded = SearchText.fold(candidate.term)
            if forms[folded] == nil { forms[folded] = candidate.term }
        }
        return forms
    }

    /// The pairs the polish pass still owes a judgement: displayed terms whose
    /// plural-stripped stem collides, minus the pairs already decided. The AI
    /// confirms each, so this side can be generous without risking a wrong
    /// merge — a false candidate is simply judged NO.
    private func pendingTermPairs() -> [(String, String)] {
        guard isAvailable else { return [] }
        let folded = Array(displayedTermForms().keys)
        var byStem: [String: [String]] = [:]
        for term in folded { byStem[Self.normalizeStem(term), default: []].append(term) }

        var pairs: [(String, String)] = []
        for group in byStem.values where group.count >= 2 {
            let sorted = group.sorted()
            for i in sorted.indices {
                for j in sorted.index(after: i) ..< sorted.endIndex {
                    let key = Self.termPairKey(sorted[i], sorted[j])
                    if termLinks[key] == nil { pairs.append((sorted[i], sorted[j])) }
                }
            }
        }
        return pairs
    }

    /// Rebuilds `termAliases` from the confirmed-same links with a small
    /// union-find, so every term in a class maps to the class's canonical key
    /// (its lexicographically smallest folded form).
    private func rebuildAliases() {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var root = x
            while let next = parent[root], next != root { root = next }
            return root
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if ra < rb { parent[rb] = ra } else { parent[ra] = rb }
        }

        for (key, same) in termLinks where same {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parent[parts[0]] == nil { parent[parts[0]] = parts[0] }
            if parent[parts[1]] == nil { parent[parts[1]] = parts[1] }
            union(parts[0], parts[1])
        }

        var aliases: [String: String] = [:]
        for term in parent.keys { aliases[term] = find(term) }
        termAliases = aliases
    }

    /// Strips a plural suffix for the candidate-collision test — Turkish
    /// `-ler/-lar` and English `-ies/-es/-s` — guarded by a minimum stem length
    /// so short words are not mangled. Over-stripping is safe: the AI gate has
    /// the final say on whether a resulting collision is a real variant.
    static func normalizeStem(_ folded: String) -> String {
        var stem = folded
        for suffix in ["ler", "lar"] where stem.hasSuffix(suffix) && stem.count - suffix.count >= 4 {
            stem = String(stem.dropLast(suffix.count))
            break
        }
        if stem.hasSuffix("ies"), stem.count - 3 >= 3 {
            stem = String(stem.dropLast(3)) + "y"
        } else if stem.hasSuffix("es"), stem.count - 2 >= 4 {
            stem = String(stem.dropLast(2))
        } else if stem.hasSuffix("s"), !stem.hasSuffix("ss"), stem.count - 1 >= 4 {
            stem = String(stem.dropLast(1))
        }
        return stem
    }

    static func termPairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    private func runLinking() async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let pairs = pendingTermPairs()
            guard !pairs.isEmpty else { return }

            isLinking = true
            pendingCount = pairs.count
            reviewedCount = 0
            var start = 0
            while start < pairs.count {
                let batch = Array(pairs[start ..< min(start + Self.batchSize, pairs.count)])
                let results = await confirmPairs(batch)
                for (key, same) in results { termLinks[key] = same }
                reviewedCount += batch.count
                rebuildAliases()
                Self.writeAliases(AliasCache(links: termLinks))
                start += Self.batchSize
            }
            isLinking = false
        }
        #endif
    }

    static func parseLinked(_ answer: String, pairs: [(String, String)]) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for (number, rest) in numbered(answer, count: pairs.count) {
            if let same = parseLinkedLine(rest) {
                let pair = pairs[number - 1]
                result[termPairKey(pair.0, pair.1)] = same
            }
        }
        return result
    }

    static func parseLinkedLine(_ line: String) -> Bool? {
        let upper = line.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.hasPrefix("YES") { return true }
        if upper.hasPrefix("NO") { return false }
        return nil
    }

    private static let linkInstructions = """
    You are given numbered pairs of medical terms. For each pair, decide \
    whether the two are the SAME term — one merely the plural, or a spelling or \
    casing variant, of the other (for example "cell" / "cells", or "nucleus" / \
    "nuclei") — rather than two different concepts. Reply one line per item: \
    the item number, ')', then YES if they are the same term, or NO. In order, \
    nothing else.
    """

    private static func linkBatchPrompt(_ pairs: [(String, String)]) -> String {
        pairs.enumerated()
            .map { index, pair in "ITEM \(index + 1)\n\(pair.0) | \(pair.1)" }
            .joined(separator: "\n\n")
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func confirmPairs(_ pairs: [(String, String)]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        do {
            let session = LanguageModelSession(instructions: Self.linkInstructions)
            let answer = try await session.respond(to: Self.linkBatchPrompt(pairs)).content
            result = Self.parseLinked(answer, pairs: pairs)
        } catch {
            // Whole-batch failure falls through to the per-item path below.
        }
        for pair in pairs where result[Self.termPairKey(pair.0, pair.1)] == nil {
            // Only record a pair the model actually answered; an unanswered one
            // is left undecided so it is retried on a later run, never merged by
            // default.
            if let decided = await confirmOne(pair) {
                result[Self.termPairKey(pair.0, pair.1)] = decided
            }
        }
        return result
    }

    @available(macOS 26, *)
    private func confirmOne(_ pair: (String, String)) async -> Bool? {
        do {
            let session = LanguageModelSession(instructions: Self.linkInstructions)
            let answer = try await session.respond(to: "1) \(pair.0) | \(pair.1)").content
            return Self.parseLinkedLine(Self.firstLine(answer))
        } catch {
            return nil
        }
    }
    #endif

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func scanPage(_ text: String) async -> [String] {
        do {
            let session = LanguageModelSession(instructions: Self.scanInstructions)
            let answer = try await session.respond(to: "PAGE:\n\(Self.clip(text))").content
            return Self.parseTerms(answer)
        } catch {
            return []
        }
    }

    @available(macOS 26, *)
    private func extractDefinition(term: String, page: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: Self.extractDefInstructions)
            let answer = try await session.respond(to: "PAGE:\n\(Self.clip(page))\nTERM: \(term)").content
            return Self.parseDefinition(Self.firstLine(answer), term: term)
        } catch {
            return nil
        }
    }

    @available(macOS 26, *)
    private func sentenceCheck(term: String, definition: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: Self.sentenceInstructions)
            let answer = try await session.respond(to: "TERM: \(term)\nDEFINITION: \(definition)").content
            return Self.parseSentence(Self.firstLine(answer))
        } catch {
            // On a model error keep what we have rather than lose the entry.
            return definition
        }
    }

    /// The final gate: the same strict "is this really a definition?" question
    /// as the deep-verification pass, asked over several sampled passes and
    /// settled by majority vote, so a lone stray "no" never drops a good entry.
    @available(macOS 26, *)
    private func gate(term: String, definition: String, page: String) async -> VerifyOutcome {
        var noVotes = 0
        var answered = 0
        var reason: Rejection?
        let options = GenerationOptions(temperature: Self.consensusTemperature)
        let prompt = "TERM: \(term)\nDEFINITION: \(definition)\nLINES:\n\(Self.clip(page))"

        for _ in 0 ..< Self.consensusPasses {
            do {
                let session = LanguageModelSession(instructions: Self.verifyInstructions)
                let answer = try await session.respond(to: prompt, options: options).content
                if let outcome = Self.parseVerifiedLine(Self.firstLine(answer)) {
                    answered += 1
                    if !outcome.keep {
                        noVotes += 1
                        if reason == nil { reason = outcome.reason }
                    }
                }
            } catch {
                // A failed pass simply does not vote.
            }
        }

        if answered == 0 { return (keep: true, reason: nil) }
        if noVotes >= Self.consensusQuorum { return (keep: false, reason: reason ?? .other) }
        return (keep: true, reason: nil)
    }
    #endif

    // MARK: Model-driven glossary — helpers, prompts, parsing

    /// A page's text, capped so the small model gets a prompt it handles well.
    /// Slides are short; this only bites on the rare wall-of-text page.
    private static func clip(_ text: String) -> String { String(text.prefix(1500)) }

    /// A stable (launch-independent) hash of a page's text, so a record can
    /// tell whether its page changed. Swift's own `Hasher` is salted per run
    /// and would make every page look changed next launch, so this is a plain
    /// FNV-1a over the bytes.
    static func fingerprint(_ text: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    private static let scanInstructions = """
    You are reading one page of a medical lecture slide. List the terms this \
    page actually DEFINES — a term the page gives a real explanation for, not \
    one it only mentions in passing. One term per line, the term only (a word \
    or short noun phrase), at most six. Do not number them. If the page defines \
    nothing, reply NONE.
    """

    private static let extractDefInstructions = """
    You are given one page of medical lecture slides and a TERM the page \
    defines. Write the definition of the TERM using ONLY what the page says, \
    as one clean, self-contained sentence. Add no facts, numbers, examples or \
    formulas of your own, and do not end by repeating the term ("… is called \
    X"). Fix obvious OCR typos only. If the page does not actually define the \
    term, reply NO.
    """

    private static let sentenceInstructions = """
    You are given a TERM and a DEFINITION written for it. If the DEFINITION is \
    a complete, self-contained, grammatical sentence that defines the term, \
    reply with it — corrected only for OCR or grammar, adding no new facts. If \
    it is a fragment, a half sentence, a bare list, or not a definition, reply \
    NO.
    """

    static func parseTerms(_ answer: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in answer.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.uppercased() != "NONE" else { continue }
            line = DefinitionExtractor.stripListMarker(line)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -•·*▪‣\t.:"))
            let key = SearchText.fold(line)
            guard key.count >= 2, line.count <= 60, seen.insert(key).inserted else { continue }
            result.append(line)
            if result.count >= 6 { break }
        }
        return result
    }

    static func parseDefinition(_ line: String, term: String) -> String? {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, firstWord(body).uppercased() != "NO" else { return nil }
        let cleaned = cleanDefinition(body, term: term)
        return cleaned.count >= 15 ? cleaned : nil
    }

    static func parseSentence(_ line: String) -> String? {
        let body = line.trimmingCharacters(in: CharacterSet(charactersIn: " -•·*\"'“”`\t"))
        guard !body.isEmpty, firstWord(body).uppercased() != "NO" else { return nil }
        return body.count >= 15 ? body : nil
    }

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

    /// For verification the model sees the finished entry — term and the
    /// definition written for it — plus the slide lines, so it can judge both
    /// whether it reads as a definition and whether the lines bear it out.
    private static func verifyPrompt(_ candidate: SlideDefinition, _ verdict: Verdict) -> String {
        "TERM: \(verdict.term)\nDEFINITION: \(verdict.definition)\nLINES:\n\(candidate.context)"
    }

    private static func verifyBatchPrompt(_ pairs: [(SlideDefinition, Verdict)]) -> String {
        pairs.enumerated()
            .map { index, pair in
                "ITEM \(index + 1)\nTERM: \(pair.1.term)\nDEFINITION: \(pair.1.definition)\nLINES:\n\(pair.0.context)"
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
    called …" or otherwise repeat the term. Do not carry any list lettering or \
    numbering ("a)", "1.") into the term. Fix obvious OCR typos only.
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

    private static let verifyInstructions = """
    You are checking finished entries for a medical glossary. Each item has a \
    TERM, the DEFINITION written for it, and the slide LINES it was taken from.

    Keep an item only when the DEFINITION is a real, self-contained definition \
    of the TERM: it says what the term is, reads as a complete sentence, and is \
    borne out by the LINES. Reject it when it is a title or heading, a bare \
    list of items or examples, a half sentence or fragment, a person's name, a \
    citation or reference, or simply not a definition of that term. When in \
    doubt, keep it.

    For each item reply on its own line: the item number, ')', then YES to keep \
    it, or NO and ONE word for what it is instead (incomplete, list, title, \
    person, citation, other). Example: `1) YES` or `2) NO title`. One line per \
    item, in order, nothing else.
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
                return Verdict(accepted: true, term: normalizeTerm(fallback.term), definition: definition, reason: nil)
            }
        }

        if line.uppercased().hasPrefix("NO") {
            return Verdict(accepted: false, term: fallback.term, definition: fallback.definition, reason: nil)
        }

        return Verdict(accepted: fallback.confidence == .high, term: fallback.term, definition: fallback.definition, reason: nil)
    }

    static func parseVerified(_ answer: String, pairs: [(SlideDefinition, Verdict)]) -> [String: VerifyOutcome] {
        var result: [String: VerifyOutcome] = [:]
        for (number, rest) in numbered(answer, count: pairs.count) {
            if let outcome = parseVerifiedLine(rest) {
                result[pairs[number - 1].0.id] = outcome
            }
        }
        return result
    }

    /// One verification line: `YES` keeps the entry, `NO <word>` demotes it
    /// with that reason, anything else is treated as no answer (`nil`).
    static func parseVerifiedLine(_ line: String) -> VerifyOutcome? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()
        if upper.hasPrefix("YES") { return (keep: true, reason: nil) }
        if upper.hasPrefix("NO") {
            let word = firstWord(String(trimmed.dropFirst(2)))
            return (keep: false, reason: word.isEmpty ? .other : Rejection(keyword: word))
        }
        return nil
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
                return Verdict(accepted: true, term: normalizeTerm(term), definition: definition, reason: nil)
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

    /// Words a definition must not end on: a trailing copula or connective
    /// means the sentence was cut mid-thought — often by the naming-tail strip
    /// above ("this group of proteins is") — so it is not self-contained.
    private static let danglingTails: Set<String> = [
        "is", "are", "was", "were", "a", "an", "the", "of", "and", "or",
        "to", "that", "which", "as", "in", "on", "with", "by",
    ]

    static func isSelfContained(_ definition: String, term: String) -> Bool {
        let words = definition.split(separator: " ")
        guard words.count >= 4 else { return false }
        if let first = words.first, fragmentLeads.contains(SearchText.fold(String(first))) {
            return false
        }
        if let last = words.last, danglingTails.contains(SearchText.fold(String(last))) {
            return false
        }
        return SearchText.fold(definition) != SearchText.fold(term)
    }

    /// Evens out a term's casing for display: an all-lowercase head is
    /// capitalised ("denaturation" → "Denaturation") and a long all-caps head
    /// is title-cased ("GENOME" → "Genome"), while short acronyms (DNA, IPSP)
    /// and mixed-case terms (B-DNA, MARs) are left exactly as the slide wrote
    /// them. The candidate id keys on the untouched term, so marks survive.
    static func normalizeTerm(_ term: String) -> String {
        // The model sometimes echoes the slide's list lettering into the term
        // ("b) Apocrine secretion"); drop it, the same way the colon path does.
        let trimmed = DefinitionExtractor.stripListMarker(term)
            .trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }
        if trimmed == trimmed.lowercased(with: L.locale) {
            return String(first).uppercased(with: L.locale) + trimmed.dropFirst()
        }
        if trimmed == trimmed.uppercased(with: L.locale),
           trimmed.count >= 5, trimmed.allSatisfy(\.isLetter) {
            // A plain all-caps word ("GENOME") is title-cased, but a
            // hyphenated or punctuated acronym ("B-DNA", "ES-complex") is
            // left alone — it is not shouting, it is spelled that way.
            return String(first).uppercased(with: L.locale) + trimmed.dropFirst().lowercased(with: L.locale)
        }
        return trimmed
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

    private nonisolated static func readPages() -> PageCache? {
        guard let data = try? Data(contentsOf: pagesURL),
              let cache = try? JSONDecoder().decode(PageCache.self, from: data),
              cache.version == PageCache().version
        else { return nil }
        return cache
    }

    private nonisolated static func writePages(_ cache: PageCache) {
        write(cache, to: pagesURL, what: "sözlük sayfaları")
    }

    private nonisolated static func readAliases() -> AliasCache? {
        guard let data = try? Data(contentsOf: aliasesURL),
              let cache = try? JSONDecoder().decode(AliasCache.self, from: data),
              cache.version == AliasCache().version
        else { return nil }
        return cache
    }

    private nonisolated static func writeAliases(_ cache: AliasCache) {
        write(cache, to: aliasesURL, what: "sözlük terim eşleşmeleri")
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
