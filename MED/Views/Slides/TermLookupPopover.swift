import SwiftUI

// MARK: - The lookup popover (paylaşımlı — macOS ve iOS)

/// What our slide glossary and the OpenStax atlas say about a selected term,
/// shown in place so studying a slide never has to break stride to look a word
/// up. Reads the same curated glossary the Sözlük screen shows and the same
/// atlas index the Atlas screen does; the buttons hand off to those screens
/// when the reader wants the full entry.
struct TermLookupPopover: View {
    let term: String
    let dismiss: () -> Void

    @Environment(GlossaryModel.self) private var glossary
    @Environment(SlideIndex.self) private var slideIndex
    @Environment(ReferenceLibrary.self) private var reference
    @Environment(AppNavigation.self) private var nav

    /// Results are held rather than computed in `body`: computing them inline
    /// ran the whole scan on every redraw and, worse, before the popover could
    /// paint — which read as a lag. Now the box shows at once, the fast slide
    /// glossary fills with it, and the atlas scan runs after a yield with a
    /// spinner in its place.
    @State private var slideDefs: [GlossaryModel.CuratedDefinition] = []
    @State private var atlasDefs: [ReferenceLibrary.Term] = []
    @State private var searchingAtlas = false
    @State private var finished = false

    private var needle: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fills the slide glossary immediately, then yields so the box and those
    /// results paint before the atlas scan — which is the slower of the two —
    /// runs behind its spinner.
    private func search() async {
        slideDefs = []
        atlasDefs = []
        finished = false
        searchingAtlas = reference.isReady

        let candidates = glossary.isAvailable ? glossary.candidates : slideIndex.definitions
        slideDefs = Array(glossary.definitions(matching: needle, in: candidates).prefix(6))

        guard reference.isReady else {
            finished = true
            return
        }

        await Task.yield()

        let all = reference.matchingTerms(needle)
        let byTerm = all.filter { SearchText.contains($0.term, query: needle) }
        atlasDefs = Array((byTerm.isEmpty ? all : byTerm).prefix(6))
        searchingAtlas = false
        finished = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(needle)
                .font(.headline)
                .textCase(nil)
                .lineLimit(2)
                .truncationMode(.tail)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !slideDefs.isEmpty {
                        source(L.pick("Slayt sözlüğü", "Slide glossary")) {
                            ForEach(slideDefs) { entry in
                                definition(term: entry.term, text: entry.definition)
                            }
                        }
                    }

                    if searchingAtlas {
                        source(L.pick("Atlas (OpenStax)", "Atlas (OpenStax)")) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(L.pick("Atlas'ta aranıyor…", "Searching the atlas…"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if !atlasDefs.isEmpty {
                        source(L.pick("Atlas (OpenStax)", "Atlas (OpenStax)")) {
                            ForEach(atlasDefs) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    definition(term: entry.term, text: entry.definition)

                                    Button(L.pick("Atlas'ta aç", "Open in atlas")) {
                                        openAtlas(at: entry)
                                    }
                                    .linkButtonStyle()
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    if finished && slideDefs.isEmpty && atlasDefs.isEmpty {
                        Text(reference.isReady
                            ? L.pick("Bu terim için tanım bulunamadı.", "No definition found for this term.")
                            : L.pick("Slayt sözlüğünde bulunamadı. Atlas henüz indirilmedi — Ayarlar'dan indirebilirsin.",
                                     "Not in the slide glossary. The atlas is not downloaded yet — you can get it in Settings."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 340)
            .task(id: needle) { await search() }

            Divider()

            HStack(spacing: 12) {
                Button(L.pick("Atlas'ta ara", "Search the atlas")) {
                    nav.openInAtlas(needle)
                    dismiss()
                }
                .disabled(!reference.isReady)

                Button(L.pick("Slaytlarda ara", "Search the slides")) {
                    nav.slideQuery = needle
                    nav.slidePage = nil
                    nav.section = .search
                    nav.readingSlide = nil
                    nav.fullScreenSlide = nil
                    dismiss()
                }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private func source(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)

            content()
        }
    }

    private func definition(term: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.callout.weight(.semibold))
                .textCase(nil)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    /// Opens the atlas PDF at the term's Key Terms page, the same jump the Atlas
    /// screen's glossary row makes.
    private func openAtlas(at entry: ReferenceLibrary.Term) {
        nav.referenceQuery = entry.term
        nav.referenceMode = .glossary
        nav.referencePage = SlidePageSelection(
            path: ReferenceLibrary.pdfURL.path(percentEncoded: false),
            page: entry.page,
            query: entry.term
        )
        nav.section = .reference
        dismiss()
    }
}
