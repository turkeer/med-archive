import SwiftUI

/// The Atlas screen: the OpenStax reference book, used four ways.
///
/// A fixed external book is a different thing from the user's own slides, so it
/// gets its own screen rather than leaking into theirs. The book is unusually
/// well structured — its own table of contents, numbered figures, and a
/// chapter-by-chapter glossary the authors wrote — so plain text search would
/// waste it. The four modes each lean on one of those structures:
///
/// - **Contents** jumps straight to a chapter or section, from the PDF's own
///   bookmarks.
/// - **Glossary** is the authors' Key Terms, an authoritative dictionary.
/// - **Figures** jumps to a figure by its number.
/// - **Search** is the full-text fallback, for anything the structure misses.
///
/// Whatever is picked, the page is drawn by `SlidePageDetail`, exactly like a
/// slide hit — the atlas PDF resolves from its absolute path with no library
/// root.
struct ReferenceView: View {
    @Binding var query: String
    @Binding var selection: SlidePageSelection?

    @Environment(ReferenceLibrary.self) private var reference

    enum Mode: String, CaseIterable, Identifiable {
        case contents, glossary, figures, search
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contents: return L.pick("İçindekiler", "Contents")
            case .glossary: return L.pick("Sözlük", "Glossary")
            case .figures:  return L.pick("Figürler", "Figures")
            case .search:   return L.pick("Ara", "Search")
            }
        }
    }

    @AppStorage("referenceMode") private var mode: Mode = .contents

    @State private var sectionResults: [ReferenceLibrary.Section] = []
    @State private var termResults: [ReferenceLibrary.Term] = []
    @State private var figureResults: [ReferenceLibrary.Figure] = []
    @State private var pageResults: [ReferenceLibrary.Hit] = []

    /// Which units and chapters are open in the Contents and Figures lists.
    /// Collapsed by default, so each list opens as a short, scannable set of
    /// units.
    @State private var expandedUnits: Set<Int> = []
    @State private var expandedChapters: Set<String> = []
    @State private var expandedFigureUnits: Set<Int> = []
    @State private var expandedFigureChapters: Set<Int> = []

    private var filtering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct Question: Equatable {
        let query: String
        let mode: Mode
        let ready: Bool
    }

    var body: some View {
        Group {
            if reference.isReady {
                ready
            } else {
                status
            }
        }
        .navigationTitle(L.pick("Atlas", "Atlas"))
    }

    // MARK: Ready

    private var ready: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            list
                .searchable(text: $query, placement: .sidebar, prompt: prompt)
        }
        .task(id: Question(query: query, mode: mode, ready: reference.isReady)) {
            recompute()
        }
    }

    private var prompt: String {
        switch mode {
        case .contents: return L.pick("Bölümlerde ara", "Filter sections")
        case .glossary: return L.pick("Terim ara", "Filter terms")
        case .figures:  return L.pick("Figür ara (ör. 11.4)", "Filter figures (e.g. 11.4)")
        case .search:   return L.pick("Atlasın içinde ara", "Search inside the atlas")
        }
    }

    private func recompute() {
        switch mode {
        case .contents: sectionResults = reference.matchingSections(query)
        case .glossary: termResults = reference.matchingTerms(query)
        case .figures:  figureResults = reference.matchingFigures(query)
        case .search:   pageResults = reference.search(query)
        }
    }

    @ViewBuilder
    private var list: some View {
        switch mode {
        case .contents: contentsList
        case .glossary: glossaryList
        case .figures:  figuresList
        case .search:   searchList
        }
    }

    // MARK: Contents

    /// The outline grouped into chapters and their sections. A level-1 entry
    /// opens a group; the level-2 entries after it are its children.
    private var contentsGroups: [(chapter: ReferenceLibrary.Section, sections: [ReferenceLibrary.Section])] {
        var groups: [(ReferenceLibrary.Section, [ReferenceLibrary.Section])] = []
        for section in sectionResults {
            if section.level <= 1 {
                groups.append((section, []))
            } else if !groups.isEmpty {
                groups[groups.count - 1].1.append(section)
            } else {
                groups.append((section, []))
            }
        }
        return groups.map { (chapter: $0.0, sections: $0.1) }
    }

    private var contentsList: some View {
        List(selection: $selection) {
            if filtering {
                // While filtering, a flat list of matches reads faster than
                // units and chapters you would have to open one by one.
                ForEach(sectionResults) { sectionRow($0, heading: $0.level <= 1) }
            } else {
                ForEach(contentsNodes) { node in
                    switch node {
                    case .loose(let chapter, let sections):
                        chapterDisclosure(chapter, sections)
                    case .unit(let unit, let chapters):
                        DisclosureGroup(isExpanded: unitExpansion(unit.number)) {
                            ForEach(chapters, id: \.chapter.id) { chapterDisclosure($0.chapter, $0.sections) }
                        } label: {
                            unitLabel(unit)
                        }
                    }
                }
            }
            attribution
        }
    }

    @ViewBuilder
    private func chapterDisclosure(
        _ chapter: ReferenceLibrary.Section,
        _ sections: [ReferenceLibrary.Section]
    ) -> some View {
        if sections.isEmpty {
            sectionRow(chapter, heading: true)
        } else {
            DisclosureGroup(isExpanded: chapterExpansion(chapter.id)) {
                ForEach(sections) { sectionRow($0, heading: false) }
            } label: {
                chapterLabel(chapter)
            }
        }
    }

    /// A unit node wraps its chapters; a loose node is a top-level entry with
    /// no unit of its own (Preface, References, the Index).
    private enum ContentsNode: Identifiable {
        case loose(ReferenceLibrary.Section, [ReferenceLibrary.Section])
        case unit(ReferenceLibrary.Unit, [(chapter: ReferenceLibrary.Section, sections: [ReferenceLibrary.Section])])
        var id: String {
            switch self {
            case .loose(let section, _): return "loose-\(section.id)"
            case .unit(let unit, _): return "unit-\(unit.number)"
            }
        }
    }

    /// The chapter groups folded under their units. Chapters of a unit are
    /// contiguous in the outline, so consecutive ones are bucketed together;
    /// anything with no unit stays loose, in place.
    private var contentsNodes: [ContentsNode] {
        let groups = contentsGroups
        let byChapter = unitByChapter
        var nodes: [ContentsNode] = []
        var i = 0
        while i < groups.count {
            if let number = chapterNumber(groups[i].chapter.title), let unit = byChapter[number] {
                var bucket: [(chapter: ReferenceLibrary.Section, sections: [ReferenceLibrary.Section])] = []
                while i < groups.count,
                      let n = chapterNumber(groups[i].chapter.title),
                      byChapter[n]?.number == unit.number {
                    bucket.append(groups[i])
                    i += 1
                }
                nodes.append(.unit(unit, bucket))
            } else {
                nodes.append(.loose(groups[i].chapter, groups[i].sections))
                i += 1
            }
        }
        return nodes
    }

    private func unitLabel(_ unit: ReferenceLibrary.Unit) -> some View {
        Text(L.pick("Ünite \(unit.number): \(unit.title)", "Unit \(unit.number): \(unit.title)"))
            .font(.headline)
    }

    private func unitExpansion(_ number: Int) -> Binding<Bool> {
        Binding(
            get: { expandedUnits.contains(number) },
            set: { if $0 { expandedUnits.insert(number) } else { expandedUnits.remove(number) } }
        )
    }

    /// The chapter number in a "Chapter 7 Axial Skeleton" title, or nil for a
    /// non-chapter entry like "Preface".
    private func chapterNumber(_ title: String) -> Int? {
        let parts = title.split(separator: " ")
        guard parts.count >= 2, parts[0].caseInsensitiveCompare("Chapter") == .orderedSame else { return nil }
        return Int(parts[1])
    }

    private var unitByChapter: [Int: ReferenceLibrary.Unit] {
        var map: [Int: ReferenceLibrary.Unit] = [:]
        for unit in reference.units {
            for chapter in unit.chapters { map[chapter] = unit }
        }
        return map
    }

    private func sectionRow(_ section: ReferenceLibrary.Section, heading: Bool) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .fontWeight(heading ? .semibold : .regular)
            Spacer(minLength: 4)
            Text("\(section.page)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .tag(SlidePageSelection(path: Self.pdfPath, page: section.page, query: ""))
    }

    private func chapterLabel(_ section: ReferenceLibrary.Section) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Text("\(section.page)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func chapterExpansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedChapters.contains(id) },
            set: { if $0 { expandedChapters.insert(id) } else { expandedChapters.remove(id) } }
        )
    }

    // MARK: Glossary

    private var glossaryList: some View {
        List(selection: $selection) {
            if termResults.isEmpty {
                empty(L.pick(
                    "Terim bulunamadı.",
                    "No term found."
                ))
            } else {
                ForEach(termResults) { term in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.term)
                            .font(.headline)
                        Text(term.definition)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                    .tag(SlidePageSelection(path: Self.pdfPath, page: term.page, query: term.term))
                }
                attribution
            }
        }
    }

    // MARK: Figures

    struct FigureGroup: Identifiable {
        let number: Int
        let title: String
        let figures: [ReferenceLibrary.Figure]
        var id: Int { number }
    }

    /// Figures grouped by chapter number, with the chapter's title for the
    /// header. Order follows the figure numbers.
    private var figureGroups: [FigureGroup] {
        var titles: [Int: String] = [:]
        let re = try? NSRegularExpression(pattern: "Chapter\\s+(\\d+)")
        for section in reference.sections where section.level <= 1 {
            guard let re,
                  let match = re.firstMatch(in: section.title, range: NSRange(section.title.startIndex..., in: section.title)),
                  let range = Range(match.range(at: 1), in: section.title),
                  let number = Int(section.title[range])
            else { continue }
            titles[number] = section.title
        }

        var order: [Int] = []
        var byChapter: [Int: [ReferenceLibrary.Figure]] = [:]
        for figure in figureResults {
            let number = Int(figure.label.split(separator: ".").first ?? "") ?? 0
            if byChapter[number] == nil { order.append(number) }
            byChapter[number, default: []].append(figure)
        }

        return order.map { number in
            FigureGroup(
                number: number,
                title: titles[number] ?? L.pick("Bölüm \(number)", "Chapter \(number)"),
                figures: byChapter[number] ?? []
            )
        }
    }

    private enum FigureNode: Identifiable {
        case loose(FigureGroup)
        case unit(ReferenceLibrary.Unit, [FigureGroup])
        var id: String {
            switch self {
            case .loose(let group): return "loose-\(group.number)"
            case .unit(let unit, _): return "unit-\(unit.number)"
            }
        }
    }

    /// Chapter figure-groups folded under their units, the same contiguous
    /// bucketing the Contents list uses.
    private var figureNodes: [FigureNode] {
        let groups = figureGroups
        let byChapter = unitByChapter
        var nodes: [FigureNode] = []
        var i = 0
        while i < groups.count {
            if let unit = byChapter[groups[i].number] {
                var bucket: [FigureGroup] = []
                while i < groups.count, byChapter[groups[i].number]?.number == unit.number {
                    bucket.append(groups[i])
                    i += 1
                }
                nodes.append(.unit(unit, bucket))
            } else {
                nodes.append(.loose(groups[i]))
                i += 1
            }
        }
        return nodes
    }

    private var figuresList: some View {
        List(selection: $selection) {
            if figureResults.isEmpty {
                empty(L.pick("Figür bulunamadı.", "No figure found."))
            } else if filtering {
                ForEach(figureResults) { figureRow($0) }
                attribution
            } else {
                ForEach(figureNodes) { node in
                    switch node {
                    case .loose(let group):
                        figureChapterDisclosure(group)
                    case .unit(let unit, let groups):
                        DisclosureGroup(isExpanded: figureUnitExpansion(unit.number)) {
                            ForEach(groups) { figureChapterDisclosure($0) }
                        } label: {
                            unitLabel(unit)
                        }
                    }
                }
                attribution
            }
        }
    }

    private func figureChapterDisclosure(_ group: FigureGroup) -> some View {
        DisclosureGroup(isExpanded: figureChapterExpansion(group.number)) {
            ForEach(group.figures) { figureRow($0) }
        } label: {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func figureUnitExpansion(_ number: Int) -> Binding<Bool> {
        Binding(
            get: { expandedFigureUnits.contains(number) },
            set: { if $0 { expandedFigureUnits.insert(number) } else { expandedFigureUnits.remove(number) } }
        )
    }

    private func figureRow(_ figure: ReferenceLibrary.Figure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.pick("Şekil \(figure.label)", "Figure \(figure.label)"))
                .font(.headline)
            if !figure.title.isEmpty {
                Text(figure.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: Self.pdfPath, page: figure.page, query: "FIGURE \(figure.label)"))
    }

    private func figureChapterExpansion(_ number: Int) -> Binding<Bool> {
        Binding(
            get: { expandedFigureChapters.contains(number) },
            set: { if $0 { expandedFigureChapters.insert(number) } else { expandedFigureChapters.remove(number) } }
        )
    }

    // MARK: Full-text search

    private var searchList: some View {
        List(selection: $selection) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                empty(L.pick(
                    "Bir terim yaz — atlasın her yerinde aranır.",
                    "Type a term — the whole atlas is searched."
                ))
            } else if pageResults.isEmpty {
                empty(L.pick(
                    "Bu terim atlasta bulunamadı. Latince karşılığını (ör. \"biceps brachii\") denemeyi dene.",
                    "This term was not found. Try the Latin form (e.g. \"biceps brachii\")."
                ))
            } else {
                ForEach(pageResults) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.pick("sayfa \(hit.page)", "page \(hit.page)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(reference.snippet(page: hit.page, query: query))
                            .font(.callout)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    .tag(SlidePageSelection(path: Self.pdfPath, page: hit.page, query: query))
                }
                attribution
            }
        }
    }

    // MARK: Pieces

    private static var pdfPath: String {
        ReferenceLibrary.pdfURL.path(percentEncoded: false)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var attribution: some View {
        Text(ReferenceLibrary.attribution)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    // MARK: Not ready

    @ViewBuilder
    private var status: some View {
        switch reference.phase {
        case .absent:
            ContentUnavailableView {
                Label(L.pick("Atlas indirilmedi", "The atlas is not downloaded"), systemImage: "book.pages")
            } description: {
                Text(L.pick(
                    "OpenStax Anatomy and Physiology 2e, slaytlarınla çalışırken ek kaynak. Yaklaşık 476 MB; bir kez indirilir, sonrası çevrimdışı çalışır.",
                    "OpenStax Anatomy and Physiology 2e, a reference for studying your slides. About 476 MB; downloaded once, then it works offline."
                ))
            } actions: {
                Button(L.pick("Atlası indir", "Download the atlas")) {
                    reference.startDownload()
                }
            }

        case .downloading(let fraction):
            VStack(spacing: 12) {
                ProgressView(value: fraction) {
                    Text(L.pick("Atlas indiriliyor…", "Downloading the atlas…"))
                }
                .frame(maxWidth: 320)

                Text("\(Int(fraction * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button(L.pick("Duraklat", "Pause")) { reference.pauseDownload() }
            }
            .padding()

        case .indexing:
            VStack(spacing: 12) {
                ProgressView()
                Text(L.pick("Atlas okunuyor…", "Reading the atlas…"))
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .failed(let message):
            ContentUnavailableView {
                Label(L.pick("İndirilemedi", "Download failed"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(L.pick("Tekrar dene", "Try again")) { reference.startDownload() }
                Link(L.pick("Kaynak sayfası", "Source page"), destination: ReferenceLibrary.sourcePageURL)
            }

        case .ready:
            EmptyView()
        }
    }
}
