import Foundation
import CoreGraphics
import Foundation
import Observation
import PDFKit

/// An external, read-only reference the student can lean on while studying
/// their own slides: OpenStax's *Anatomy and Physiology 2e*.
///
/// It is deliberately kept apart from `SlideIndex` and from the archive. This
/// is not the user's material — it is a fixed book everyone gets the same
/// copy of — so it never appears among their lectures, is never attachable to
/// a session, and never shows up in "slides missing" or the ordinary search.
///
/// **Nothing of the book ships inside the app.** The licence is CC BY-NC-SA,
/// so redistributing the PDF, or a text index derived from it, would drag the
/// whole app under ShareAlike. Instead the user downloads the original PDF
/// from OpenStax with one button, and the app reads its text **on their own
/// machine**. The index that comes out never leaves the computer, so no part
/// of the book is distributed and the licence is untouched. Keeping the app
/// free of ads and subscriptions is what keeps the NonCommercial clause met.
///
/// Reading the text is fast: the OpenStax PDF is born-digital and carries a
/// real text layer, so there is no OCR and no hours-long wait — the whole
/// book is read in a minute or so, once, after the download.
@MainActor
@Observable
final class ReferenceLibrary {

    // MARK: Catalogue

    /// The book, as OpenStax names it.
    static let title = "Anatomy and Physiology 2e"
    static let publisher = "OpenStax"
    static let licenseName = "CC BY-NC-SA 4.0"

    /// Where the "Atlası indir" button pulls the PDF from — the direct asset
    /// URL OpenStax's own CMS hands out for this book. If OpenStax ever moves
    /// it the download fails cleanly and the UI points at the book page.
    static let downloadURL = URL(string: "https://assets.openstax.org/oscms-prodcms/media/documents/anatomy-and-physiology-2e_-_WEB.pdf")!

    /// The human page, for the "where this came from" link and a fallback when
    /// the direct download no longer resolves.
    static let sourcePageURL = URL(string: "https://openstax.org/details/books/anatomy-and-physiology-2e")!

    /// The size as the server last reported it (~476 MB). Used only to show a
    /// sensible percentage before the response's own length is known, and to
    /// warn the user what they are about to download.
    static let expectedBytes: Int64 = 476_335_014

    /// A one-line credit, shown wherever the book's pages are. CC BY asks for
    /// attribution; this is it.
    static let attribution = "\(title) · \(publisher) (Rice University) · \(licenseName)"

    // MARK: State

    /// Where the library is in its lifecycle. One value the UI can switch on.
    enum Phase: Equatable {
        /// Not downloaded yet (or the file was removed).
        case absent
        /// Downloading, with the fraction done so far (0...1).
        case downloading(Double)
        /// Downloaded, now reading the text out of it.
        case indexing
        /// Searchable.
        case ready
        /// Something went wrong; the string is for the user to read.
        case failed(String)
    }

    private(set) var phase: Phase = .absent

    /// How many pages the book has, once read.
    private(set) var pageCount = 0

    // MARK: Storage

    /// Everything lives beside the store, under its own folder, like the slide
    /// index — derived, disposable, not part of the archive.
    ///
    /// `nonisolated` so the background reader and writer can reach the paths
    /// without hopping to the main actor — they hold no state, just build a URL.
    nonisolated static var directory: URL {
        StoreLocation.directory.appending(path: "Reference", directoryHint: .isDirectory)
    }

    /// The downloaded book itself. The viewer draws its pages from here, and
    /// `SlidePageDetail` resolves this absolute path with no library root.
    nonisolated static var pdfURL: URL {
        directory.appending(path: "anatomy-and-physiology-2e.pdf")
    }

    nonisolated private static var indexURL: URL {
        directory.appending(path: "openstax.json")
    }

    /// Where a cancelled or interrupted download leaves its progress, so the
    /// button can pick up where it stopped rather than restarting 476 MB.
    nonisolated private static var resumeURL: URL {
        directory.appending(path: "download.resume")
    }

    // MARK: Index (in memory)

    /// One entry per page: the raw text, as the reader sees it.
    private var pages: [String] = []

    /// The same, folded once for searching — case- and diacritic-insensitive,
    /// Turkish-aware — so a keystroke never folds the whole book again.
    private var foldedPages: [String] = []

    /// The book's own table of contents — its PDF bookmarks — flattened to a
    /// list of chapters and their sections, each with the page it opens on.
    /// Jump-to-section is built on this.
    private(set) var sections: [Section] = []

    /// Every figure, found by its all-caps "FIGURE X.X" caption, mapped to the
    /// page it sits on.
    private(set) var figures: [Figure] = []

    /// The chapter-end "Key Terms" glossaries the authors wrote, parsed into
    /// term and definition. An authoritative dictionary, not one guessed from
    /// slides — which is why it can stand in for the Latin-terminology idea.
    private(set) var terms: [Term] = []

    /// The book's units — the top grouping above chapters. They are not in the
    /// PDF's bookmarks, only in its Contents listing, so they are parsed from
    /// there: a "UNIT n Title" line owns the "CHAPTER n" lines that follow it.
    private(set) var units: [Unit] = []

    /// One chapter or section of the book, from its own bookmarks.
    struct Section: Codable, Sendable, Hashable, Identifiable {
        /// 1 for a chapter, 2 for a section inside it.
        let level: Int
        let title: String
        /// 1-based PDF page it opens on.
        let page: Int
        var id: String { "\(page)#\(title)" }
    }

    /// One figure and the page its caption sits on.
    struct Figure: Codable, Sendable, Hashable, Identifiable {
        /// "11.4" — chapter and number, as the book prints it.
        let label: String
        /// The caption's title, best-effort.
        let title: String
        let page: Int
        var id: String { label }
    }

    /// One Key Terms entry: a term and the definition the authors gave it.
    struct Term: Codable, Sendable, Hashable, Identifiable {
        let term: String
        let definition: String
        /// The page of the Key Terms list it was taken from — the jump target.
        let page: Int
        /// The chapter it belongs to, for context.
        let chapter: String
        var id: String { "\(chapter)#\(term)" }
    }

    /// One unit of the book and the chapter numbers it contains.
    struct Unit: Codable, Sendable, Hashable, Identifiable {
        let number: Int
        let title: String
        let chapters: [Int]
        var id: Int { number }
    }

    private struct Cache: Codable, Sendable {
        /// Bumped when the stored shape changes, so an old file is discarded
        /// and rebuilt. 1 held only page text; 2 added the outline, figures and
        /// Key Terms; 3 added the units; 4 reads the Key Terms from the content
        /// stream (bold + ToUnicode) instead of PDFKit, which gave nothing;
        /// 5 strips stray leading punctuation off a term; 6 keeps a definition
        /// that continues across a page break; 7–8 end the region at the
        /// "Chapter Review" heading (even when it is split into many runs),
        /// not at a page edge; 9 keeps Greek letters (a different font) inside
        /// the term.
        var version = 9
        var pages: [String]
        var sections: [Section] = []
        var figures: [Figure] = []
        var terms: [Term] = []
        var units: [Unit] = []
    }

    private var downloader: Downloader?

    init() {
        loadIfPresent()
    }

    // MARK: Lifecycle

    var hasPDF: Bool {
        FileManager.default.fileExists(atPath: Self.pdfURL.path(percentEncoded: false))
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .indexing: return true
        case .absent, .ready, .failed: return false
        }
    }

    /// Reads whatever is already on disk at launch, without touching the
    /// network. A present PDF with a valid index is ready at once; a present
    /// PDF with no usable index is read again (cheap, no OCR).
    private func loadIfPresent() {
        guard hasPDF else { phase = .absent; return }

        if let cache = Self.readIndex() {
            adopt(cache)
            phase = .ready
        } else {
            index()
        }
    }

    // MARK: Download

    /// Starts (or resumes) the one-time download. Safe to call again while it
    /// runs — it does nothing.
    func startDownload() {
        guard downloader == nil, !isReady else { return }

        try? FileManager.default.createDirectory(
            at: Self.directory, withIntermediateDirectories: true
        )

        phase = .downloading(0)

        let resume = try? Data(contentsOf: Self.resumeURL)

        let worker = Downloader(
            url: Self.downloadURL,
            destination: Self.pdfURL,
            expected: Self.expectedBytes,
            resumeData: resume,
            onProgress: { [weak self] fraction in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            },
            onFinish: { [weak self] outcome in
                guard let self else { return }
                self.downloader = nil
                switch outcome {
                case .success:
                    try? FileManager.default.removeItem(at: Self.resumeURL)
                    self.index()
                case .paused(let data):
                    try? data.write(to: Self.resumeURL, options: .atomic)
                    self.phase = .absent
                case .failure(let message):
                    self.phase = .failed(message)
                }
            }
        )
        downloader = worker
        worker.start()
    }

    /// Stops the download but keeps what came down, so it can be resumed.
    func pauseDownload() {
        downloader?.pause()
    }

    /// Throws away the downloaded book and its index. The next download starts
    /// clean.
    func removeDownload() {
        downloader?.pause()
        downloader = nil
        let manager = FileManager.default
        for url in [Self.pdfURL, Self.indexURL, Self.resumeURL] {
            try? manager.removeItem(at: url)
        }
        pages = []
        foldedPages = []
        sections = []
        figures = []
        terms = []
        units = []
        pageCount = 0
        phase = .absent
    }

    // MARK: Indexing

    /// Reads the book off the main thread: its page text (for searching and
    /// snippets), its bookmarks (the outline), its figure captions and its
    /// Key Terms glossaries. No OCR — the OpenStax PDF has its own text layer,
    /// so the whole book is read in about a minute.
    private func index() {
        phase = .indexing
        let source = Self.pdfURL

        Task.detached(priority: .utility) {
            let cache = Self.buildIndex(from: source)
            if let cache, !cache.pages.isEmpty { Self.writeIndex(cache) }

            await MainActor.run {
                if let cache, !cache.pages.isEmpty {
                    self.adopt(cache)
                    self.phase = .ready
                } else {
                    self.phase = .failed(L.pick(
                        "İndirilen dosya okunamadı.",
                        "The downloaded file could not be read."
                    ))
                }
            }
        }
    }

    private nonisolated static func buildIndex(from url: URL) -> Cache? {
        guard let document = PDFDocument(url: url) else { return nil }

        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            pages.append(document.page(at: index)?.string ?? "")
        }

        let sections = extractOutline(document)
        return Cache(
            pages: pages,
            sections: sections,
            figures: extractFigures(pages),
            terms: extractTerms(document, sections: sections),
            units: extractUnits(pages, sections: sections)
        )
    }

    /// Reads the unit → chapter grouping from the Contents listing, which the
    /// bookmarks leave out. Walks the Contents pages in order: a "UNIT n Title"
    /// line opens a unit and every "CHAPTER n" line until the next unit belongs
    /// to it.
    private nonisolated static func extractUnits(_ pages: [String], sections: [Section]) -> [Unit] {
        let contentsStart = sections.first(where: {
            $0.title.caseInsensitiveCompare("Contents") == .orderedSame
        })?.page ?? 1
        let firstChapter = sections.first(where: {
            $0.level <= 1 && $0.title.range(of: "Chapter", options: .caseInsensitive) != nil
        })?.page ?? contentsStart

        let lower = max(1, contentsStart)
        let upper = max(lower, firstChapter - 1)
        guard lower <= pages.count else { return [] }

        guard
            let unitRe = try? NSRegularExpression(pattern: "^UNIT\\s+(\\d+)\\s+(.+)$", options: [.anchorsMatchLines]),
            let chapRe = try? NSRegularExpression(pattern: "^CHAPTER\\s+(\\d+)", options: [.anchorsMatchLines])
        else { return [] }

        var order: [Int] = []
        var titles: [Int: String] = [:]
        var chapters: [Int: [Int]] = [:]
        var current: Int?
        // A unit title can wrap onto the next line(s) in the Contents, so lines
        // between a "UNIT n" line and its first "CHAPTER" line are appended to
        // the title.
        var appendingTitle = false

        for pageNumber in lower...min(upper, pages.count) {
            for rawLine in pages[pageNumber - 1].components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let range = NSRange(line.startIndex..., in: line)

                if let m = unitRe.firstMatch(in: line, range: range),
                   let rn = Range(m.range(at: 1), in: line), let n = Int(line[rn]),
                   let rt = Range(m.range(at: 2), in: line) {
                    current = n
                    if titles[n] == nil { order.append(n) }
                    titles[n] = String(line[rt]).trimmingCharacters(in: .whitespaces)
                    appendingTitle = true
                } else if let m = chapRe.firstMatch(in: line, range: range),
                          let rn = Range(m.range(at: 1), in: line), let n = Int(line[rn]),
                          let unit = current {
                    appendingTitle = false
                    if !(chapters[unit]?.contains(n) ?? false) {
                        chapters[unit, default: []].append(n)
                    }
                } else if appendingTitle, let unit = current, !line.isEmpty {
                    titles[unit] = (titles[unit].map { $0 + " " } ?? "") + line
                }
            }
        }

        return order.map {
            Unit(number: $0, title: (titles[$0] ?? "Unit \($0)").capitalized, chapters: chapters[$0] ?? [])
        }
    }

    /// Flattens the PDF's bookmark tree into chapters (level 1) and their
    /// sections (level 2), each with the page it opens on.
    private nonisolated static func extractOutline(_ document: PDFDocument) -> [Section] {
        guard let root = document.outlineRoot else { return [] }

        var out: [Section] = []
        func walk(_ node: PDFOutline, level: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty,
                   let page = child.destination?.page {
                    out.append(Section(level: level, title: label, page: document.index(for: page) + 1))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 1)
        return out
    }

    /// Finds every figure by its all-caps "FIGURE X.X" caption. The in-text
    /// references use the title-case "Figure X.X", so matching the upper-case
    /// form lands on the caption — the page the figure is actually on.
    private nonisolated static func extractFigures(_ pages: [String]) -> [Figure] {
        guard let regex = try? NSRegularExpression(
            pattern: "FIGURE\\s+(\\d+\\.\\d+)\\s*([^\\n]{0,90})"
        ) else { return [] }

        var out: [Figure] = []
        var seen: Set<String> = []

        for (index, text) in pages.enumerated() {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: match.range(at: 1))
                guard seen.insert(label).inserted else { continue }

                var title = match.range(at: 2).location != NSNotFound
                    ? ns.substring(with: match.range(at: 2))
                    : ""
                // Keep the caption's title up to the first sub-figure marker or
                // the first sentence break.
                for cut in [" (a)", " (b)", "(a)", "(b)", ". "] {
                    if let r = title.range(of: cut) { title = String(title[..<r.lowerBound]); break }
                }
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)

                out.append(Figure(label: label, title: title, page: index + 1))
            }
        }

        return out.sorted { figureOrder($0.label) < figureOrder($1.label) }
    }

    private nonisolated static func figureOrder(_ label: String) -> (Int, Int) {
        let parts = label.split(separator: ".")
        return (Int(parts.first ?? "") ?? 0, Int(parts.last ?? "") ?? 0)
    }

    /// Parses the chapter-end "Key Terms" glossaries. The term is set in bold
    /// and the definition in regular type — but PDFKit throws that distinction
    /// away (it hands back one flat run with the two merged). So the page's
    /// content stream is scanned directly: the font each text run is drawn with
    /// reveals bold, and the font's ToUnicode table turns the subset glyph
    /// codes back into readable text. Each bold run starts a new entry. The
    /// region is bounded by the outline: a "Key Terms" bookmark up to the next.
    private nonisolated static func extractTerms(_ document: PDFDocument, sections: [Section]) -> [Term] {
        guard let url = document.documentURL,
              let cgDocument = CGPDFDocument(url as CFURL)
        else { return [] }

        var out: [Term] = []

        for (i, section) in sections.enumerated()
        where section.title.caseInsensitiveCompare("Key Terms") == .orderedSame {
            let start = section.page
            let next = (i + 1 < sections.count) ? sections[i + 1].page : start
            let chapter = sections[..<i].last(where: { $0.level == 1 })?.title ?? ""

            var currentTerm: String?
            var currentDefinition = ""
            var lastWasBold = false
            var headingText = ""

            func flush() {
                defer { currentTerm = nil; currentDefinition = ""; lastWasBold = false }
                guard let raw = currentTerm else { return }
                // A bold symbol run (a stray ")" or "-)") can glue itself to the
                // front of a term: drop everything before the first letter, and
                // discard a run that has no letters at all.
                guard let firstLetter = raw.firstIndex(where: { $0.isLetter }) else { return }
                let term = String(raw[firstLetter...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = currentDefinition
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                guard !term.isEmpty, !definition.isEmpty, term.count <= 60 else { return }
                out.append(Term(term: term, definition: definition, page: start, chapter: chapter))
            }

            // Key Terms can share its last page with the start of "Chapter
            // Review", so the region is scanned through the next bookmark's
            // page and ended precisely when that heading appears. A page-number
            // bound alone would either cut the last terms off or pull the
            // review text into the final definition.
            var stopped = false
            for pageNumber in start...max(start, next) where !stopped {
                guard let page = cgDocument.page(at: pageNumber) else { continue }

                for run in KeyTermScanner.runs(on: page) {
                    // A term is any bold run that is not a heading. Headings
                    // use the Mulish display face; body text — including the
                    // Greek letters set in DejaVu inside a term such as
                    // "beta (β)-oxidation" — is anything else. So "not Mulish"
                    // is what keeps those Greek runs inside the term instead of
                    // mistaking them for a heading and dropping them.
                    let isTermFont = run.base.range(of: "Mulish", options: .caseInsensitive) == nil

                    if run.bold, isTermFont {
                        headingText = ""
                        let trimmed = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        // The running header ("2 • Key Terms 53") is bold body
                        // text too. It is page furniture, often sitting right
                        // between a definition and its continuation at the top
                        // of the next page, so it is skipped *without* ending
                        // the term — flushing here would drop the continuation.
                        if trimmed.lowercased().contains("openstax")
                            || trimmed.contains("•") || (trimmed.first?.isNumber ?? false) {
                            lastWasBold = false
                            continue
                        }
                        if lastWasBold, currentTerm != nil {
                            // A term split across runs stays one term.
                            currentTerm! += run.text
                        } else {
                            flush()
                            currentTerm = run.text
                        }
                        lastWasBold = true
                    } else if run.bold {
                        // A display-face heading, which the PDF often splits
                        // into many one- or two-letter runs ("Chap", "t",
                        // "er R", …). Accumulate them so an end-of-chapter
                        // heading is recognised even when split: the region ends
                        // there, which is what stops "Chapter Review" body text
                        // from bleeding into the last term.
                        headingText += run.text
                        let squashed = headingText.lowercased().filter { !$0.isWhitespace }
                        if squashed.contains("chapterreview") || squashed.contains("reviewquestions")
                            || squashed.contains("criticalthinking") || squashed.contains("interactivelink") {
                            flush()
                            stopped = true
                            break
                        }
                        lastWasBold = false
                    } else {
                        headingText = ""
                        if currentTerm != nil { currentDefinition += run.text }
                        lastWasBold = false
                    }
                }
            }
            flush()
        }

        // Keep the first of each term, alphabetical for the list.
        var seen: Set<String> = []
        return out
            .filter { seen.insert(SearchText.fold($0.term)).inserted }
            .sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    }

    private func adopt(_ cache: Cache) {
        pages = cache.pages
        foldedPages = cache.pages.map(SearchText.fold)
        pageCount = cache.pages.count
        sections = cache.sections
        figures = cache.figures
        terms = cache.terms
        units = cache.units
    }

    // MARK: Searching

    /// One page that answers a search.
    struct Hit: Identifiable, Hashable {
        /// One-based, as a reader counts.
        let page: Int
        /// How many of the searched terms this page carries.
        let terms: Int
        var id: Int { page }
    }

    /// Pages of the book matching `query`, best coverage first, then in reading
    /// order. Comma means "any of these", exactly as the slide search box does
    /// — the rule is shared through `SlideIndex.terms(in:)` so the two screens
    /// cannot drift apart.
    func search(_ query: String) -> [Hit] {
        let terms = SlideIndex.terms(in: query)
        guard !terms.isEmpty, !foldedPages.isEmpty else { return [] }

        var hits: [Hit] = []
        for (index, page) in foldedPages.enumerated() {
            let found = terms.filter { page.contains($0) }
            guard !found.isEmpty else { continue }
            hits.append(Hit(page: index + 1, terms: found.count))
        }

        return hits.sorted {
            $0.terms != $1.terms ? $0.terms > $1.terms : $0.page < $1.page
        }
    }

    /// Sections whose title matches `query`; all of them for an empty query,
    /// so the contents list stays browsable.
    func matchingSections(_ query: String) -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sections }
        return sections.filter { SearchText.contains($0.title, query: needle) }
    }

    /// Key Terms matching `query` in their term or definition; all of them for
    /// an empty query.
    func matchingTerms(_ query: String) -> [Term] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return terms }
        return terms.filter {
            SearchText.contains($0.term, query: needle)
                || SearchText.contains($0.definition, query: needle)
        }
    }

    /// Figures matching `query` in their number or title; all of them for an
    /// empty query.
    func matchingFigures(_ query: String) -> [Figure] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return figures }
        return figures.filter {
            SearchText.contains($0.label, query: needle)
                || SearchText.contains($0.title, query: needle)
        }
    }

    /// The line a hit sits in, for the list to show without opening the page.
    func snippet(page: Int, query: String) -> String {
        guard page >= 1, page <= pages.count else { return "" }

        let terms = SlideIndex.terms(in: query)
        let folded = foldedPages[page - 1]
        let present = terms.first { folded.contains($0) } ?? terms.first ?? query

        return Self.snippet(of: pages[page - 1], around: present)
    }

    /// A readable line from `page` around the first occurrence of `query`.
    /// Same approach as `SlideIndex`: the match is located with Foundation's
    /// folded search so the range lands in the original text, and the opening
    /// of the page is shown when that search cannot find it.
    private nonisolated static func snippet(of page: String, around query: String) -> String {
        let clean = page
            .replacingOccurrences(of: "\u{FFFC}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let before = 45
        let after = 75

        guard let found = clean.range(
            of: query.trimmingCharacters(in: .whitespacesAndNewlines),
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) else {
            return String(clean.prefix(before + after)).trimmingCharacters(in: .whitespaces)
        }

        let start = clean.index(found.lowerBound, offsetBy: -before, limitedBy: clean.startIndex)
            ?? clean.startIndex
        let end = clean.index(found.upperBound, offsetBy: after, limitedBy: clean.endIndex)
            ?? clean.endIndex

        var text = String(clean[start..<end]).trimmingCharacters(in: .whitespaces)
        if start > clean.startIndex { text = "…" + text }
        if end < clean.endIndex { text += "…" }
        return text
    }

    // MARK: Disk

    private nonisolated static func readIndex() -> Cache? {
        guard let data = try? Data(contentsOf: indexURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == Cache(pages: []).version,
              !cache.pages.isEmpty
        else { return nil }
        return cache
    }

    private nonisolated static func writeIndex(_ cache: Cache) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try JSONEncoder().encode(cache).write(to: indexURL, options: .atomic)
        } catch {
            // An index that cannot be cached is rebuilt next launch from the
            // PDF that is already here; the feature still works for this run.
            print("MED: atlas fihristi yazılamadı — \(error)")
        }
    }
}

// MARK: - Downloader

/// A single large download with live progress and resume support.
///
/// Its own class rather than async/await because the only way to both watch
/// progress and resume a part-finished 476 MB file is `URLSessionDownloadTask`
/// with a delegate. Callbacks arrive off the main thread and are hopped back.
private final class Downloader: NSObject, URLSessionDownloadDelegate {

    enum Outcome {
        case success
        /// Stopped on purpose; the data resumes the download later.
        case paused(Data)
        case failure(String)
    }

    private let url: URL
    private let destination: URL
    private let expected: Int64
    private let resumeData: Data?
    private let onProgress: (Double) -> Void
    private let onFinish: (Outcome) -> Void

    /// Guards against reporting a finish twice: a cancel fires both the resume
    /// handler and `didCompleteWithError`, and only one should be delivered.
    private var finished = false

    private lazy var session = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil
    )
    private var task: URLSessionDownloadTask?

    init(
        url: URL,
        destination: URL,
        expected: Int64,
        resumeData: Data?,
        onProgress: @escaping (Double) -> Void,
        onFinish: @escaping (Outcome) -> Void
    ) {
        self.url = url
        self.destination = destination
        self.expected = expected
        self.resumeData = resumeData
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func start() {
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            // Some CDNs refuse the default networking user agent; the plain
            // browser pair is what the asset URL answered 200 to.
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://openstax.org/", forHTTPHeaderField: "Referer")
            task = session.downloadTask(with: request)
        }
        task?.resume()
    }

    func pause() {
        task?.cancel(byProducingResumeData: { [weak self] data in
            guard let self else { return }
            if let data {
                self.deliver(.paused(data))
            } else {
                // Nothing to resume from; treat it as a clean stop.
                self.deliver(.failure(L.pick("İndirme durduruldu.", "The download was stopped.")))
            }
        })
    }

    private func deliver(_ outcome: Outcome) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.session.finishTasksAndInvalidate()
            self.onFinish(outcome)
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        guard total > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(total), 0), 1)
        DispatchQueue.main.async { [weak self] in self?.onProgress(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temporary file is removed as soon as this method returns, so the
        // move has to happen here and now, not on another queue.
        let manager = FileManager.default
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                deliver(.failure(L.pick(
                    "Sunucu dosyayı vermedi (kod \(response.statusCode)).",
                    "The server did not return the file (code \(response.statusCode))."
                )))
                return
            }
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: location, to: destination)
            deliver(.success)
        } catch {
            deliver(.failure(error.localizedDescription))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        // A deliberate pause surfaces here too as a cancellation; the resume
        // handler already delivered the outcome, so this one is ignored.
        if (error as NSError).code == NSURLErrorCancelled { return }
        deliver(.failure(error.localizedDescription))
    }
}

// MARK: - Key Terms scanner

/// Reads a Key Terms page's text runs with their boldness, straight from the
/// PDF content stream — the one place the term/definition distinction survives,
/// since PDFKit flattens it into one Helvetica run. Each run carries whether
/// its font is bold and its text, decoded through the font's ToUnicode table
/// because the glyphs are subset codes rather than ASCII.
private enum KeyTermScanner {
    final class Font {
        let bold: Bool
        let base: String
        let map: [Int: String]
        init(bold: Bool, base: String, map: [Int: String]) {
            self.bold = bold; self.base = base; self.map = map
        }
    }

    final class ScanState {
        var fonts: [String: Font] = [:]
        var bold = false
        var base = ""
        var map: [Int: String] = [:]
        var runs: [(bold: Bool, base: String, text: String)] = []
    }

    static func runs(on page: CGPDFPage) -> [(bold: Bool, base: String, text: String)] {
        let state = ScanState()

        if let pageDict = page.dictionary {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let resources {
                var fonts: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
                    CGPDFDictionaryApplyBlock(fonts, { key, object, _ in
                        var font: CGPDFDictionaryRef?
                        guard CGPDFObjectGetValue(object, .dictionary, &font), let font else { return true }
                        var baseName: UnsafePointer<Int8>?
                        let base = CGPDFDictionaryGetName(font, "BaseFont", &baseName)
                            ? (baseName.map { String(cString: $0) } ?? "") : ""
                        var map: [Int: String] = [:]
                        var stream: CGPDFStreamRef?
                        if CGPDFDictionaryGetStream(font, "ToUnicode", &stream), let stream {
                            var format = CGPDFDataFormat.raw
                            if let data = CGPDFStreamCopyData(stream, &format) {
                                map = parseToUnicode(data as Data)
                            }
                        }
                        state.fonts[String(cString: key)] = Font(bold: base.contains("Bold"), base: base, map: map)
                        return true
                    }, nil)
                }
            }
        }

        let stream = CGPDFContentStreamCreateWithPage(page)
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        CGPDFOperatorTableSetCallback(table, "Tf", setFont)
        CGPDFOperatorTableSetCallback(table, "Tj", showText)
        CGPDFOperatorTableSetCallback(table, "'", showText)
        CGPDFOperatorTableSetCallback(table, "TJ", showArray)

        let info = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFOperatorTableRelease(table)
        CGPDFContentStreamRelease(stream)

        return state.runs
    }

    /// Turns a ToUnicode CMap into a code → text map. Handles the two forms
    /// these fonts use: single `bfchar` pairs and `bfrange` runs.
    static func parseToUnicode(_ data: Data) -> [Int: String] {
        guard let text = String(data: data, encoding: .isoLatin1) else { return [:] }
        var map: [Int: String] = [:]
        let whole = NSRange(text.startIndex..., in: text)

        if let charBlock = try? NSRegularExpression(pattern: "beginbfchar(.*?)endbfchar", options: [.dotMatchesLineSeparators]),
           let pair = try? NSRegularExpression(pattern: "<([0-9A-Fa-f]+)>\\s*<([0-9A-Fa-f]+)>") {
            for block in charBlock.matches(in: text, range: whole) {
                guard let bodyRange = Range(block.range(at: 1), in: text) else { continue }
                let body = String(text[bodyRange])
                for m in pair.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                    guard let cr = Range(m.range(at: 1), in: body), let ur = Range(m.range(at: 2), in: body),
                          let code = Int(body[cr], radix: 16) else { continue }
                    map[code] = unicode(fromHex: String(body[ur]))
                }
            }
        }

        if let rangeBlock = try? NSRegularExpression(pattern: "beginbfrange(.*?)endbfrange", options: [.dotMatchesLineSeparators]),
           let triple = try? NSRegularExpression(pattern: "<([0-9A-Fa-f]+)>\\s*<([0-9A-Fa-f]+)>\\s*<([0-9A-Fa-f]+)>") {
            for block in rangeBlock.matches(in: text, range: whole) {
                guard let bodyRange = Range(block.range(at: 1), in: text) else { continue }
                let body = String(text[bodyRange])
                for m in triple.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                    guard let lr = Range(m.range(at: 1), in: body), let hr = Range(m.range(at: 2), in: body),
                          let dr = Range(m.range(at: 3), in: body),
                          let lo = Int(body[lr], radix: 16), let hi = Int(body[hr], radix: 16),
                          let base = UInt32(body[dr], radix: 16), hi >= lo
                    else { continue }
                    for code in lo...hi {
                        if let scalar = Unicode.Scalar(base + UInt32(code - lo)) {
                            map[code] = String(scalar)
                        }
                    }
                }
            }
        }

        return map
    }

    /// Hex of UTF-16BE code units: "0061" → "a", "00660069" → "fi".
    static func unicode(fromHex hex: String) -> String {
        let chars = Array(hex)
        var units: [UInt16] = []
        var i = 0
        while i + 4 <= chars.count {
            units.append(UInt16(String(chars[i..<i+4]), radix: 16) ?? 0)
            i += 4
        }
        return String(decoding: units, as: UTF16.self)
    }
}

private func keyTermDecode(_ string: CGPDFStringRef, _ map: [Int: String]) -> String {
    guard let ptr = CGPDFStringGetBytePtr(string) else { return "" }
    let length = CGPDFStringGetLength(string)
    var out = ""
    out.reserveCapacity(length)
    for i in 0..<length { out += map[Int(ptr[i])] ?? "" }
    return out
}

private let setFont: CGPDFOperatorCallback = { scanner, info in
    guard let info else { return }
    let state = Unmanaged<KeyTermScanner.ScanState>.fromOpaque(info).takeUnretainedValue()
    var size: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &size)
    var name: UnsafePointer<Int8>?
    if CGPDFScannerPopName(scanner, &name), let name, let font = state.fonts[String(cString: name)] {
        state.bold = font.bold
        state.base = font.base
        state.map = font.map
    }
}

private let showText: CGPDFOperatorCallback = { scanner, info in
    guard let info else { return }
    let state = Unmanaged<KeyTermScanner.ScanState>.fromOpaque(info).takeUnretainedValue()
    var string: CGPDFStringRef?
    if CGPDFScannerPopString(scanner, &string), let string {
        state.runs.append((state.bold, state.base, keyTermDecode(string, state.map)))
    }
}

private let showArray: CGPDFOperatorCallback = { scanner, info in
    guard let info else { return }
    let state = Unmanaged<KeyTermScanner.ScanState>.fromOpaque(info).takeUnretainedValue()
    var array: CGPDFArrayRef?
    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
    var combined = ""
    for i in 0..<CGPDFArrayGetCount(array) {
        var string: CGPDFStringRef?
        if CGPDFArrayGetString(array, i, &string), let string {
            combined += keyTermDecode(string, state.map)
        }
    }
    state.runs.append((state.bold, state.base, combined))
}
