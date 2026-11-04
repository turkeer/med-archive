import SwiftData
import SwiftUI

/// A glossary built from your own slides: every term they define, with the
/// slide it came from one tap away.
///
/// It leans on nothing but the slide text `SlideIndex` already holds — no
/// outside dictionary, no network, nothing to license. Choosing a definition
/// opens its slide in the detail column with the term marked.
///
/// Two modes. **Sözlük** is the clean result — the definitions the model
/// confirmed, minus the ones you hid, plus any you kept by hand. **Gözden
/// geçir** is the pile the model set aside, sorted by why (a real definition
/// cut short, a title, a list…), so a wrongly-rejected term is easy to find and
/// put back. Your hide/keep choices are yours and survive a re-review.
struct GlossaryView: View {
    @Binding var query: String
    @Binding var selection: SlidePageSelection?

    @Environment(SlideIndex.self) private var slideIndex
    @Environment(GlossaryModel.self) private var glossaryModel

    /// Needed to place a slide under its lecture — and so its course and
    /// committee — for the crossover mode. The same `relativePath → Lecture`
    /// map that `SlideSearchView` builds.
    @Query private var files: [LectureFile]

    @AppStorage("glossaryShowsUncertain") private var showsUncertain = false
    /// In the crossover tab: show the ones you dismissed (to bring them back)
    /// instead of the live list.
    @AppStorage("glossaryShowsHiddenCrossovers") private var showsHiddenCrossovers = false
    @State private var mode: Mode = .glossary

    /// Crossover points are heavier to compute (they scan the slide text), so
    /// they are built once into here and refreshed when the index changes or
    /// the tab is opened — not on every keystroke in the search box.
    @State private var crossovers: [CommitteeIntersection.Point] = []

    /// The crossover scan runs on the main actor and can take a second or two
    /// over hundreds of terms × thousands of pages, so it is built lazily —
    /// once per index build, only when its tab is actually shown, and never
    /// twice at once. `crossoversBuiltFor` is the `lastBuilt` stamp the current
    /// `crossovers` were computed against.
    @State private var isBuildingCrossovers = false
    @State private var crossoversBuiltFor: Date?

    private enum Mode: String, CaseIterable, Identifiable {
        case glossary
        case review
        case crossovers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .glossary:   return L.pick("Sözlük", "Glossary")
            case .review:     return L.pick("Gözden geçir", "Review")
            case .crossovers: return L.pick("Kesişimler", "Crossovers")
            }
        }
    }

    /// One slide a definition came from — a place to jump to.
    private struct Source: Identifiable, Hashable {
        let path: String
        let page: Int
        var id: String { "\(path)#\(page)" }
    }

    /// One definition of a term. The same wording can be repeated on several
    /// slides (a lecturer restating it), so a single entry carries *all* the
    /// slides it appears on rather than showing the duplicate twice; `ids`
    /// holds every candidate it stands for, so hiding it hides them all.
    private struct Entry: Identifiable {
        let id: String
        let ids: [String]
        let term: String
        let definition: String
        let sources: [Source]
        let isRecognised: Bool
        let pending: Bool
        let uncertain: Bool
        let kept: Bool
        var primary: Source { sources[0] }
    }

    private struct TermGroup: Identifiable {
        let id: String
        let term: String
        let entries: [Entry]
    }

    var body: some View {
        List(selection: $selection) {
            if glossaryModel.isReviewing {
                reviewProgress
            }

            switch mode {
            case .glossary:   glossaryContent
            case .review:     reviewContent
            case .crossovers: crossoverContent
            }
        }
        .searchable(text: $query, prompt: L.pick("Terim ara", "Search a term"))
        .navigationTitle(L.glossary)
        .task(id: slideIndex.lastBuilt) {
            // With the on-device model, the glossary is built by reading every
            // page (the thorough, resumable pass). Without it, there is nothing
            // to run — the regex high-confidence tier shows directly.
            if glossaryModel.isAvailable {
                glossaryModel.buildGlossary(from: slideIndex.pages)
            }
            // The crossover scan is NOT run here: it is heavy and only shown on
            // its own tab, so building it on every glossary open froze the view.
            // The index just changed, so the current build is stale — drop its
            // stamp and rebuild lazily, right now only if that tab is showing.
            crossoversBuiltFor = nil
            if mode == .crossovers { buildCrossoversIfNeeded() }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .crossovers { buildCrossoversIfNeeded() }
        }
        .toolbar {
            ToolbarItem {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if mode == .glossary {
                ToolbarItem {
                    Toggle(isOn: $showsUncertain) {
                        Label(
                            glossaryModel.isAvailable
                                ? L.pick("İncelenmemişler", "Unreviewed")
                                : L.pick("Şüpheliler", "Uncertain"),
                            systemImage: "questionmark.circle"
                        )
                    }
                    .toggleStyle(.button)
                }
            }

            // Visible while the mode is on too, so after unhiding the last one
            // you can still flip the toggle back off instead of being stuck.
            if mode == .crossovers, glossaryModel.hasHiddenCrossovers || showsHiddenCrossovers {
                ToolbarItem {
                    Toggle(isOn: $showsHiddenCrossovers) {
                        Label(L.pick("Gizlenenler", "Hidden"), systemImage: "eye.slash")
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }

    // MARK: Glossary mode

    @ViewBuilder
    private var glossaryContent: some View {
        let groups = termGroups(from: shownEntries)

        if groups.isEmpty {
            glossaryEmptyState
        } else {
            summary(groups)

            ForEach(groups) { group in
                Section {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        definitionRow(entry, number: group.entries.count > 1 ? index + 1 : nil)
                    }
                } header: {
                    Text(group.term).font(.headline).textCase(nil)
                }
            }
        }
    }

    /// The glossary's candidate source: what the model produced by reading the
    /// pages when it is available, else the regex high-confidence tier. The
    /// rest of the view reads these the same way either way — a verdict lookup
    /// decides what shows — so only this one line changes between the two.
    private var candidates: [SlideDefinition] {
        glossaryModel.isAvailable ? glossaryModel.candidates : slideIndex.definitions
    }

    /// The definitions worth showing: confirmed (or heuristic) ones minus the
    /// ones you hid, plus any you kept by hand.
    private var shownEntries: [Entry] {
        var items: [Entry] = []

        for candidate in candidates {
            if glossaryModel.isKept(candidate.id) {
                let verdict = glossaryModel.verdict(for: candidate.id)
                items.append(entry(candidate, term: verdict?.term ?? candidate.term,
                                   definition: verdict?.definition ?? candidate.definition,
                                   pending: false, uncertain: false, kept: true))
                continue
            }
            if glossaryModel.isHidden(candidate.id) { continue }

            if glossaryModel.isAvailable {
                if let verdict = glossaryModel.verdict(for: candidate.id) {
                    guard verdict.accepted else { continue }
                    items.append(entry(candidate, term: verdict.term, definition: verdict.definition,
                                       pending: false, uncertain: false, kept: false))
                } else if showsUncertain {
                    items.append(entry(candidate, term: candidate.term, definition: candidate.definition,
                                       pending: true, uncertain: false, kept: false))
                }
            } else if showsUncertain || candidate.confidence == .high {
                items.append(entry(candidate, term: candidate.term, definition: candidate.definition,
                                   pending: false, uncertain: candidate.confidence == .uncertain, kept: false))
            }
        }

        return filtered(items)
    }

    // MARK: Review mode

    @ViewBuilder
    private var reviewContent: some View {
        if !glossaryModel.isAvailable {
            Text(L.pick(
                "Gözden geçirme listesi modelin ayırdıklarından oluşur; bu sistemde model yok.",
                "The review pile comes from what the model set aside; there is no model on this system."
            ))
                .foregroundStyle(.secondary)
        } else {
            let buckets = rejectionBuckets
            let hidden = hiddenEntries

            if buckets.isEmpty && hidden.isEmpty {
                Text(glossaryModel.isReviewing
                    ? L.pick("İnceleme sürüyor…", "The review is still running…")
                    : L.pick("Ayrılmış bir şey yok.", "Nothing set aside."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(buckets, id: \.reason) { bucket in
                    Section {
                        ForEach(bucket.entries) { entry in
                            rejectRow(entry)
                        }
                    } header: {
                        Text("\(name(for: bucket.reason)) (\(bucket.entries.count))").textCase(nil)
                    }
                }

                if !hidden.isEmpty {
                    Section {
                        ForEach(hidden) { entry in
                            rejectRow(entry)
                        }
                    } header: {
                        Text("\(L.pick("Gizlediklerin", "Hidden by you")) (\(hidden.count))").textCase(nil)
                    }
                }
            }
        }
    }

    private struct Bucket { let reason: GlossaryModel.Rejection; let entries: [Entry] }

    /// The model's rejects you have not kept, grouped by why, incomplete first.
    private var rejectionBuckets: [Bucket] {
        var byReason: [GlossaryModel.Rejection: [Entry]] = [:]

        for candidate in candidates {
            guard !glossaryModel.isKept(candidate.id), !glossaryModel.isHidden(candidate.id),
                  let verdict = glossaryModel.verdict(for: candidate.id), !verdict.accepted
            else { continue }

            let reason = GlossaryModel.Rejection(keyword: verdict.reason ?? "")
            byReason[reason, default: []].append(
                entry(candidate, term: candidate.term, definition: candidate.definition,
                      pending: false, uncertain: false, kept: false)
            )
        }

        return GlossaryModel.Rejection.allCases.compactMap { reason in
            guard let entries = byReason[reason] else { return nil }
            return Bucket(reason: reason, entries: filtered(entries))
        }
        .filter { !$0.entries.isEmpty }
    }

    private var hiddenEntries: [Entry] {
        let items = candidates
            .filter { glossaryModel.isHidden($0.id) }
            .map { candidate -> Entry in
                let verdict = glossaryModel.verdict(for: candidate.id)
                return entry(candidate, term: verdict?.term ?? candidate.term,
                             definition: verdict?.definition ?? candidate.definition,
                             pending: false, uncertain: false, kept: false)
            }
        return filtered(items)
    }

    private func name(for reason: GlossaryModel.Rejection) -> String {
        switch reason {
        case .incomplete: return L.pick("Yarım tanım", "Incomplete")
        case .list:       return L.pick("Liste", "List")
        case .title:      return L.pick("Başlık", "Heading")
        case .person:     return L.pick("Kişi", "Person")
        case .citation:   return L.pick("Kaynak", "Citation")
        case .other:      return L.pick("Diğer", "Other")
        }
    }

    // MARK: Crossover mode

    /// Slide path → its lecture, the same map `SlideSearchView` builds, so a
    /// definition can be placed under its course and committee.
    private var lecturesByPath: [String: Lecture] {
        Dictionary(
            files.compactMap { file -> (String, Lecture)? in
                guard let lecture = file.lecture else { return nil }
                return (file.relativePath, lecture)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Builds the crossover points only when they are stale for the current
    /// index build, and never two runs at once. The scan blocks the main actor,
    /// so it is kicked to the next runloop tick: the list paints the "computing"
    /// row first, then the scan runs. Nothing here fires until the crossovers
    /// tab is shown, which is what keeps opening the glossary tab instant.
    private func buildCrossoversIfNeeded() {
        guard !isBuildingCrossovers, crossoversBuiltFor != slideIndex.lastBuilt else { return }
        isBuildingCrossovers = true
        Task { @MainActor in
            rebuildCrossovers()
            crossoversBuiltFor = slideIndex.lastBuilt
            isBuildingCrossovers = false
        }
    }

    /// Rebuilds the crossover points from the curated glossary and the slide
    /// text. Call it through `buildCrossoversIfNeeded()`, not directly.
    private func rebuildCrossovers() {
        crossovers = CommitteeIntersection.points(
            from: glossaryModel.curatedTerms(from: candidates),
            lecturesByPath: lecturesByPath,
            locate: { slideIndex.phraseLocations($0) }
        )
    }

    /// The points to show: the dismissed ones when revealing them, otherwise
    /// the live ones, then narrowed by the search box.
    private var shownCrossovers: [CommitteeIntersection.Point] {
        let base = crossovers.filter {
            showsHiddenCrossovers
                ? glossaryModel.isCrossoverHidden($0.id)
                : !glossaryModel.isCrossoverHidden($0.id)
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return base }
        return base.filter { SearchText.contains($0.term, query: needle) }
    }

    @ViewBuilder
    private var crossoverContent: some View {
        let points = shownCrossovers

        if isBuildingCrossovers {
            crossoverBuilding
        } else if points.isEmpty {
            crossoverEmptyState
        } else {
            crossoverSummary(points)

            ForEach(points) { point in
                Section {
                    ForEach(point.occurrences) { occurrence in
                        crossoverRow(occurrence)
                    }
                } header: {
                    crossoverHeader(point)
                }
            }
        }
    }

    private func crossoverHeader(_ point: CommitteeIntersection.Point) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.term).font(.headline).textCase(nil)
            HStack(spacing: 6) {
                Circle().fill(Color(hex: point.committeeColorHex)).frame(width: 7, height: 7)
                Text(point.committeeLabel.isEmpty ? point.committeeName : point.committeeLabel)
                Text("·")
                Text(L.pick("\(point.courseCount) ders", "\(point.courseCount) courses"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
        .contextMenu {
            if glossaryModel.isCrossoverHidden(point.id) {
                Button(L.pick("Geri al", "Unhide")) { glossaryModel.setCrossoverHidden(point.id, false) }
            } else {
                Button(L.pick("Gizle", "Hide")) { glossaryModel.setCrossoverHidden(point.id, true) }
            }
        }
    }

    private func crossoverRow(_ occurrence: CommitteeIntersection.Occurrence) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(occurrence.courseColorHex.map { Color(hex: $0) } ?? Color.secondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(occurrence.courseName.isEmpty
                         ? L.pick("Ders yok", "No course")
                         : occurrence.courseName)
                        .font(.callout.weight(.medium))
                    badge(occurrence.isDefinition
                          ? L.pick("tanım", "defined")
                          : L.pick("geçiyor", "mentioned"))
                }
                Text(crossoverSource(occurrence)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: occurrence.path, page: occurrence.page, query: occurrence.term))
    }

    private func crossoverSource(_ occurrence: CommitteeIntersection.Occurrence) -> String {
        let name = (occurrence.path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let where_ = occurrence.lectureTitle.isEmpty ? stem : "\(occurrence.lectureTitle) · \(stem)"
        return "\(where_) · " + L.pick("s.\(occurrence.page)", "p.\(occurrence.page)")
    }

    private func crossoverSummary(_ points: [CommitteeIntersection.Point]) -> some View {
        Text(L.pick("\(points.count) kesişen terim",
                    "\(points.count) crossover terms"))
            .font(.caption).foregroundStyle(.secondary)
    }

    private var crossoverBuilding: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L.pick("Kesişimler hesaplanıyor…", "Computing crossovers…"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var crossoverEmptyState: some View {
        if slideIndex.isWorking {
            Text(L.pick("Slaytlar hâlâ okunuyor, birazdan tekrar bak.",
                        "The slides are still being read; check back in a moment."))
                .foregroundStyle(.secondary)
        } else if showsHiddenCrossovers {
            Text(L.pick("Gizlenen kesişim yok.", "No hidden crossovers."))
                .foregroundStyle(.secondary)
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(L.pick("“\(query)” ile eşleşen kesişim yok.",
                        "No crossover matches “\(query)”."))
                .foregroundStyle(.secondary)
        } else {
            Text(L.pick(
                "Henüz kesişim yok. Bir terim, aynı komitede birden fazla farklı derste geçtiğinde burada belirir — derslerin komite ve derse bağlı, slaytları okunmuş olmalı.",
                "No crossovers yet. A term shows up here when it appears in more than one course of the same committee — your lectures need a committee and course, and their slides need to be read."
            ))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Shared row building

    private func entry(_ candidate: SlideDefinition, term: String, definition: String, pending: Bool, uncertain: Bool, kept: Bool) -> Entry {
        Entry(id: candidate.id, ids: [candidate.id], term: term, definition: definition,
              sources: [Source(path: candidate.path, page: candidate.page)],
              isRecognised: candidate.isRecognised,
              pending: pending, uncertain: uncertain, kept: kept)
    }

    private func filtered(_ items: [Entry]) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return items }
        return items.filter {
            SearchText.contains($0.term, query: needle) || SearchText.contains($0.definition, query: needle)
        }
    }

    private func termGroups(from items: [Entry]) -> [TermGroup] {
        // Group on the canonical key, so a term and its confirmed plural land
        // together; the heading is then the spelling that appears on the most
        // slides.
        Dictionary(grouping: items) { glossaryModel.canonicalKey(for: SearchText.fold($0.term)) }
            .map { key, group in
                let deduped = mergeDuplicates(group)
                let ordered = deduped.sorted {
                    $0.primary.path == $1.primary.path
                        ? $0.primary.page < $1.primary.page
                        : $0.primary.path < $1.primary.path
                }
                return TermGroup(id: key, term: headingTerm(for: deduped), entries: ordered)
            }
            .sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    /// The heading for a group: when several spellings are linked together (a
    /// singular and its plural), the one that appears on the most slides wins,
    /// ties going to the shorter (usually the singular).
    private func headingTerm(for entries: [Entry]) -> String {
        var bySpelling: [String: (term: String, sources: Int)] = [:]
        for entry in entries {
            let key = SearchText.fold(entry.term)
            bySpelling[key] = (entry.term, (bySpelling[key]?.sources ?? 0) + entry.sources.count)
        }
        let best = bySpelling.values.max {
            $0.sources != $1.sources ? $0.sources < $1.sources : $0.term.count > $1.term.count
        }
        return displayTerm(best?.term ?? entries.first?.term ?? "")
    }

    /// Collapses entries whose definition is word-for-word the same (the same
    /// wording a lecturer put on more than one slide) into one, keeping every
    /// slide it came from as a source. The merged entry carries all its
    /// candidate ids, so hiding or keeping it covers every copy at once.
    private func mergeDuplicates(_ entries: [Entry]) -> [Entry] {
        var order: [String] = []
        var byDefinition: [String: [Entry]] = [:]
        for entry in entries {
            let key = SearchText.fold(entry.definition)
            if byDefinition[key] == nil { order.append(key) }
            byDefinition[key, default: []].append(entry)
        }

        return order.map { key in
            let group = byDefinition[key]!
            guard group.count > 1 else { return group[0] }

            let sources = group.flatMap(\.sources)
                .reduce(into: [Source]()) { acc, source in
                    if !acc.contains(source) { acc.append(source) }
                }
                .sorted { $0.path == $1.path ? $0.page < $1.page : $0.path < $1.path }
            let first = group[0]
            return Entry(
                id: first.id,
                ids: group.flatMap(\.ids),
                term: first.term,
                definition: first.definition,
                sources: sources,
                // A copy read cleanly from any slide's text is not "from image";
                // kept/pending stand if they hold for every copy.
                isRecognised: group.allSatisfy(\.isRecognised),
                pending: group.allSatisfy(\.pending),
                uncertain: group.contains { $0.uncertain },
                kept: group.contains { $0.kept }
            )
        }
    }

    private func definitionRow(_ entry: Entry, number: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if number != nil || entry.pending || entry.uncertain || entry.isRecognised || entry.kept {
                HStack(spacing: 6) {
                    if let number {
                        Text("\(number).").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if entry.kept { badge(L.pick("elle eklendi", "kept")) }
                    if entry.pending { badge(L.pick("inceleniyor", "reviewing")) }
                    else if entry.uncertain { badge(L.pick("şüpheli", "uncertain")) }
                    if entry.isRecognised { badge(L.pick("görüntüden", "from image")) }
                }
            }

            Text(displayDefinition(entry.definition)).font(.callout).lineLimit(4).foregroundStyle(.primary)
            // Every slide this exact definition appears on — one line each, so a
            // repeated definition reads as a single entry with several sources.
            ForEach(entry.sources) { source in
                Text(self.source(source)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: entry.primary.path, page: entry.primary.page, query: entry.term))
        .contextMenu {
            if entry.kept {
                Button(L.pick("Sözlükten çıkar", "Remove from glossary")) {
                    entry.ids.forEach { glossaryModel.setKept($0, false) }
                }
            } else {
                Button(L.pick("Gizle", "Hide")) {
                    entry.ids.forEach { glossaryModel.setHidden($0, true) }
                }
            }
        }
    }

    private func rejectRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTerm(entry.term)).font(.callout.weight(.medium))
            Text(displayDefinition(entry.definition)).font(.callout).lineLimit(3).foregroundStyle(.secondary)
            Text(source(entry.primary)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: entry.primary.path, page: entry.primary.page, query: entry.term))
        .contextMenu {
            if glossaryModel.isHidden(entry.id) {
                Button(L.pick("Geri al", "Unhide")) { glossaryModel.setHidden(entry.id, false) }
            } else {
                Button(L.pick("Sözlüğe ekle", "Add to glossary")) { glossaryModel.setKept(entry.id, true) }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14), in: Capsule())
    }

    private func source(_ source: Source) -> String {
        let name = (source.path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return "\(stem) · " + L.pick("s.\(source.page)", "p.\(source.page)")
    }

    // MARK: Capitalisation

    /// Upper-cases the first letter, but only when the first word is plainly
    /// lower-case — so `cytosol` becomes `Cytosol` while `pKa`, `mRNA`, `SAM`
    /// and `DNA`, whose casing carries meaning, are left exactly as they are.
    private func capitalisedFirstWordAware(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isLowercase else { return text }
        let firstWord = text.prefix { !$0.isWhitespace }
        guard firstWord.allSatisfy({ $0.isLowercase || !$0.isLetter }) else { return text }
        return String(first).uppercased(with: L.locale) + text.dropFirst()
    }

    private func displayTerm(_ raw: String) -> String { capitalisedFirstWordAware(raw) }
    private func displayDefinition(_ raw: String) -> String { capitalisedFirstWordAware(raw) }

    // MARK: Progress + empty

    private var reviewProgress: some View {
        let label = glossaryModel.isBuilding
            ? L.pick("Slaytlar okunuyor… ", "Reading the slides… ")
            : glossaryModel.isLinking
            ? L.pick("Terimler eşleştiriliyor… ", "Linking terms… ")
            : glossaryModel.isVerifying
                ? L.pick("Tanımlar bir daha gözden geçiriliyor… ", "Re-checking definitions… ")
                : glossaryModel.isClassifying
                    ? L.pick("Ayrılanlar sınıflandırılıyor… ", "Classifying what was set aside… ")
                    : L.pick("Model tanımları inceliyor… ", "The model is reviewing… ")
        return HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label + "\(glossaryModel.reviewedCount)/\(glossaryModel.pendingCount)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summary(_ groups: [TermGroup]) -> some View {
        let definitions = groups.reduce(0) { $0 + $1.entries.count }
        return Text(L.pick("\(groups.count) terim · \(definitions) tanım",
                           "\(groups.count) terms · \(definitions) definitions"))
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var glossaryEmptyState: some View {
        if slideIndex.isWorking {
            Text(L.pick("Slaytlar hâlâ okunuyor, birazdan tekrar bak.", "The slides are still being read; check back in a moment."))
                .foregroundStyle(.secondary)
        } else if candidates.isEmpty {
            Text(L.pick(
                "Slaytlardan henüz tanım çıkmadı. Slaytların kitaplık klasöründe okunur hâlde olduğundan emin ol.",
                "No definitions came out of the slides yet. Make sure your slides are readable in the library folder."
            ))
                .foregroundStyle(.secondary)
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(L.pick("“\(query)” ile eşleşen tanım yok.", "No definition matches “\(query)”."))
                .foregroundStyle(.secondary)
        } else if glossaryModel.isAvailable {
            Text(L.pick(
                "Model henüz bir tanım onaylamadı. İnceleme sürüyorsa bekle; ya da sağ üstten incelenmemişleri aç.",
                "The model hasn't confirmed any definitions yet. Wait for the review, or turn on unreviewed at the top right."
            ))
                .foregroundStyle(.secondary)
        } else {
            Text(L.pick(
                "Kesin tanım görünmüyor. Sağ üstten “Şüpheliler”i açarak daha fazlasını görebilirsin.",
                "No high-confidence definitions. Turn on “Uncertain” at the top right to see more."
            ))
                .foregroundStyle(.secondary)
        }
    }
}
