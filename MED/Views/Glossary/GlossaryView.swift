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

    @AppStorage("glossaryShowsUncertain") private var showsUncertain = false
    @State private var mode: Mode = .glossary

    private enum Mode: String, CaseIterable, Identifiable {
        case glossary
        case review
        var id: String { rawValue }
        var title: String {
            switch self {
            case .glossary: return L.pick("Sözlük", "Glossary")
            case .review:   return L.pick("Gözden geçir", "Review")
            }
        }
    }

    /// One definition of a term, with where it came from and how it got here.
    private struct Entry: Identifiable {
        let id: String
        let term: String
        let definition: String
        let path: String
        let page: Int
        let isRecognised: Bool
        let pending: Bool
        let uncertain: Bool
        let kept: Bool
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
            case .glossary: glossaryContent
            case .review:   reviewContent
            }
        }
        .searchable(text: $query, prompt: L.pick("Terim ara", "Search a term"))
        .navigationTitle(L.glossary)
        .task(id: slideIndex.lastBuilt) {
            glossaryModel.review(slideIndex.definitions)
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

    /// The definitions worth showing: confirmed (or heuristic) ones minus the
    /// ones you hid, plus any you kept by hand.
    private var shownEntries: [Entry] {
        let candidates = slideIndex.definitions
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

        for candidate in slideIndex.definitions {
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
        let items = slideIndex.definitions
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

    // MARK: Shared row building

    private func entry(_ candidate: SlideDefinition, term: String, definition: String, pending: Bool, uncertain: Bool, kept: Bool) -> Entry {
        Entry(id: candidate.id, term: term, definition: definition, path: candidate.path,
              page: candidate.page, isRecognised: candidate.isRecognised,
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
        Dictionary(grouping: items) { SearchText.fold($0.term) }
            .map { key, group in
                let ordered = group.sorted { $0.path == $1.path ? $0.page < $1.page : $0.path < $1.path }
                return TermGroup(id: key, term: displayTerm(ordered[0].term), entries: ordered)
            }
            .sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
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
            Text(source(entry)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: entry.path, page: entry.page, query: entry.term))
        .contextMenu {
            if entry.kept {
                Button(L.pick("Sözlükten çıkar", "Remove from glossary")) { glossaryModel.setKept(entry.id, false) }
            } else {
                Button(L.pick("Gizle", "Hide")) { glossaryModel.setHidden(entry.id, true) }
            }
        }
    }

    private func rejectRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTerm(entry.term)).font(.callout.weight(.medium))
            Text(displayDefinition(entry.definition)).font(.callout).lineLimit(3).foregroundStyle(.secondary)
            Text(source(entry)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: entry.path, page: entry.page, query: entry.term))
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

    private func source(_ entry: Entry) -> String {
        let name = (entry.path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return "\(stem) · " + L.pick("s.\(entry.page)", "p.\(entry.page)")
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
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text((glossaryModel.isClassifying
                ? L.pick("Ayrılanlar sınıflandırılıyor… ", "Classifying what was set aside… ")
                : L.pick("Model tanımları inceliyor… ", "The model is reviewing… "))
                + "\(glossaryModel.reviewedCount)/\(glossaryModel.pendingCount)")
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
        } else if slideIndex.definitions.isEmpty {
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
