import SwiftUI

/// A glossary built from your own slides: every term they define, with the
/// slide it came from one tap away.
///
/// It leans on nothing but the slide text `SlideIndex` already holds — no
/// outside dictionary, no network, nothing to license. Choosing a definition
/// opens its slide in the detail column with the term marked, so "where is this
/// from, say more" is answered in context rather than taken on trust.
///
/// Two layers decide what shows. A pattern matcher casts a wide net over the
/// slides; then, where the system has one, the on-device model (`GlossaryModel`)
/// sifts those candidates into real definitions and tidies them. With no model
/// the matcher's own high-confidence tier shows instead, and the "unreviewed"
/// toggle reveals the rest — nothing is ever silently dropped.
///
/// Entries are gathered by term: one headword, and under it every slide that
/// defined it, numbered. A term taught in two places is one thing to look up,
/// not two rows that happen to share a name.
struct GlossaryView: View {
    @Binding var query: String
    @Binding var selection: SlidePageSelection?

    @Environment(SlideIndex.self) private var slideIndex
    @Environment(GlossaryModel.self) private var glossaryModel

    /// Remembered across launches: whether to mix in the ones the model has
    /// not confirmed (or, with no model, the heuristic's uncertain tier).
    @AppStorage("glossaryShowsUncertain") private var showsUncertain = false

    /// One definition of a term, with where it came from.
    private struct Entry: Identifiable {
        let id: String
        let term: String        // raw, for highlighting on the slide
        let definition: String
        let path: String
        let page: Int
        let isRecognised: Bool
        let pending: Bool
        let uncertain: Bool
    }

    /// A headword and its definitions.
    private struct TermGroup: Identifiable {
        let id: String          // folded term
        let term: String        // display form
        let entries: [Entry]
    }

    var body: some View {
        let groups = termGroups

        List(selection: $selection) {
            if glossaryModel.isReviewing {
                reviewProgress
            }

            if groups.isEmpty {
                emptyState
            } else {
                summary(groups)

                ForEach(groups) { group in
                    Section {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry, number: group.entries.count > 1 ? index + 1 : nil)
                        }
                    } header: {
                        Text(group.term)
                            .font(.headline)
                            .textCase(nil)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: L.pick("Terim ara", "Search a term"))
        .navigationTitle(L.glossary)
        .task(id: slideIndex.lastBuilt) {
            glossaryModel.review(slideIndex.definitions)
        }
        .toolbar {
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
                .help(glossaryModel.isAvailable
                    ? L.pick(
                        "Modelin henüz onaylamadığı adayları da listeye katar.",
                        "Also lists candidates the model has not confirmed yet."
                    )
                    : L.pick(
                        "Kesin olmayan, elle gözden geçirmeye değer tanımları da katar.",
                        "Also lists the less certain definitions, worth a manual glance."
                    ))
            }
        }
    }

    // MARK: Data

    /// The candidates that survive the model (or the heuristic tiers), as flat
    /// entries, before they are gathered by term.
    private var entries: [Entry] {
        let candidates = slideIndex.definitions
        var items: [Entry] = []

        if glossaryModel.isAvailable {
            for candidate in candidates {
                if let verdict = glossaryModel.verdict(for: candidate.id) {
                    guard verdict.accepted else { continue }
                    items.append(entry(from: candidate, term: verdict.term, definition: verdict.definition, pending: false, uncertain: false))
                } else if showsUncertain {
                    items.append(entry(from: candidate, term: candidate.term, definition: candidate.definition, pending: true, uncertain: false))
                }
            }
        } else {
            for candidate in candidates where showsUncertain || candidate.confidence == .high {
                items.append(entry(from: candidate, term: candidate.term, definition: candidate.definition, pending: false, uncertain: candidate.confidence == .uncertain))
            }
        }

        let deduped = subsumed(items)

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return deduped }

        return deduped.filter {
            SearchText.contains($0.term, query: needle)
                || SearchText.contains($0.definition, query: needle)
        }
    }

    /// Collapses entries whose definition text is identical to a single, most
    /// specific one.
    ///
    /// The same wording turns up under two terms when a slide title bleeds into
    /// the heading below it — `Strong acids: …` can arrive both as itself and,
    /// shorn of its qualifier, as `Acids: …`. When the explanation is word for
    /// word the same, the longer term is the real one, so that is the one kept.
    /// Genuinely different definitions of a term keep their own entries and
    /// still list together under the headword.
    private func subsumed(_ items: [Entry]) -> [Entry] {
        Dictionary(grouping: items) { SearchText.fold($0.definition) }
            .values
            .map { group in
                group.max { left, right in
                    if left.term.count != right.term.count {
                        return left.term.count < right.term.count
                    }
                    // Deterministic tie-break: the earliest slide wins, so the
                    // kept entry does not shuffle between launches.
                    return (left.path, left.page) > (right.path, right.page)
                }!
            }
    }

    private func entry(from candidate: SlideDefinition, term: String, definition: String, pending: Bool, uncertain: Bool) -> Entry {
        Entry(
            id: candidate.id,
            term: term,
            definition: definition,
            path: candidate.path,
            page: candidate.page,
            isRecognised: candidate.isRecognised,
            pending: pending,
            uncertain: uncertain
        )
    }

    /// Entries gathered under one headword per term, alphabetical, with each
    /// term's definitions in a stable order.
    private var termGroups: [TermGroup] {
        let grouped = Dictionary(grouping: entries) { SearchText.fold($0.term) }

        return grouped
            .map { key, items in
                let ordered = items.sorted {
                    $0.path == $1.path ? $0.page < $1.page : $0.path < $1.path
                }
                return TermGroup(id: key, term: displayTerm(ordered[0].term), entries: ordered)
            }
            .sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    // MARK: Capitalisation

    /// Upper-cases the first letter, but only when the first word is plainly
    /// lower-case — so `cytosol` becomes `Cytosol` while `pKa`, `mRNA`, `SAM`
    /// and `DNA`, whose casing carries meaning, are left exactly as they are.
    private func capitalisedFirstWordAware(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first.isLowercase else { return text }

        let firstWord = text.prefix { !$0.isWhitespace }
        let plainLowercase = firstWord.allSatisfy { $0.isLowercase || !$0.isLetter }
        guard plainLowercase else { return text }

        return String(first).uppercased(with: L.locale) + text.dropFirst()
    }

    private func displayTerm(_ raw: String) -> String {
        capitalisedFirstWordAware(raw)
    }

    private func displayDefinition(_ raw: String) -> String {
        capitalisedFirstWordAware(raw)
    }

    // MARK: Rows

    private var reviewProgress: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(L.pick(
                "Model tanımları inceliyor… \(glossaryModel.reviewedCount)/\(glossaryModel.pendingCount)",
                "The model is reviewing definitions… \(glossaryModel.reviewedCount)/\(glossaryModel.pendingCount)"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(_ groups: [TermGroup]) -> some View {
        let terms = groups.count
        let definitions = groups.reduce(0) { $0 + $1.entries.count }

        return Text(L.pick(
            "\(terms) terim · \(definitions) tanım",
            "\(terms) terms · \(definitions) definitions"
        ))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func entryRow(_ entry: Entry, number: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if number != nil || entry.pending || entry.uncertain || entry.isRecognised {
                HStack(spacing: 6) {
                    if let number {
                        Text("\(number).")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if entry.pending {
                        badge(L.pick("inceleniyor", "reviewing"))
                    } else if entry.uncertain {
                        badge(L.pick("şüpheli", "uncertain"))
                    }

                    if entry.isRecognised {
                        badge(L.pick("görüntüden", "from image"))
                    }
                }
            }

            Text(displayDefinition(entry.definition))
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.primary)

            Text(source(path: entry.path, page: entry.page))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: entry.path, page: entry.page, query: entry.term))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14), in: Capsule())
    }

    private func source(path: String, page: Int) -> String {
        let name = (path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return "\(stem) · " + L.pick("s.\(page)", "p.\(page)")
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
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
