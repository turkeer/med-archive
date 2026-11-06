import Observation
import PDFKit
import SwiftUI
#if canImport(UIKit)
import UIKit
import PencilKit
#endif

// Bu dosyanın tamamı (uygulama içi PDF okuyucu) şimdilik macOS-only: NSView
// tabanlı `PDFView` sarmalayıcıları, NSMenu ile terim arama vb. iPad'de gerçek
// okuyucu Faz 5'te gelecek (spike'taki PencilKit okuyucudan). O zamana dek iOS
// aşağıdaki yer tutucuyla derlensin diye bütün macOS uygulaması tek #if içinde.
#if os(macOS)
import AppKit

/// The page a slide hit points at, shown where the chosen record normally is.
///
/// Quick Look and "open in the default app" can both show the file, and
/// neither can open it *at a page* — which is the one thing a page-level
/// search has to be able to do. So the page is drawn here, with the matches
/// marked on it, and read with a real reader's controls: a live page count,
/// jump-to-page, zoom, a thumbnail rail, and stepping between the matches.
struct SlidePageDetail: View {
    let selection: SlidePageSelection?

    @Environment(LibraryRoot.self) private var library

    /// One controller per shown page, driving the PDF view from the chrome
    /// around it. `@State` so it survives redraws; a new file just reloads it.
    @State private var controller = PDFReaderController()
    @State private var showsThumbnails = false
    @State private var pageField = ""

    var body: some View {
        if let selection, let url = resolve(selection.path) {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                page(selection, at: url)
            } else {
                missing(url)
            }
        } else {
            SelectionPlaceholder(text: L.pick(
                "Soldaki listeden bir sayfa seç.",
                "Pick a page from the list on the left."
            ))
        }
    }

    private func page(_ selection: SlidePageSelection, at url: URL) -> some View {
        VStack(spacing: 0) {
            header(selection, url: url)

            Divider()

            HStack(spacing: 0) {
                if showsThumbnails {
                    PDFThumbnailPane(controller: controller)
                        .frame(width: 136)
                        .background(.background)

                    Divider()
                }

                SlidePDF(
                    url: url,
                    page: selection.page,
                    highlight: selection.query,
                    controller: controller
                )
            }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .onChange(of: controller.currentPage) { _, page in
            pageField = String(page)
        }
    }

    // MARK: Header / controls

    private func header(_ selection: SlidePageSelection, url: URL) -> some View {
        HStack(spacing: 10) {
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if controller.matchCount > 0 {
                matchStepper
            }

            pageStepper

            zoomControls

            Button {
                showsThumbnails.toggle()
            } label: {
                Image(systemName: showsThumbnails ? "sidebar.squares.left" : "squares.leading.rectangle")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Küçük resimleri göster/gizle", "Show or hide thumbnails"))

            fileMenu(url)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// The live "12 / 48", editable so a number can be typed to jump.
    private var pageStepper: some View {
        HStack(spacing: 3) {
            Button {
                controller.previousPage()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Önceki sayfa", "Previous page"))

            TextField("", text: $pageField)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 36)
                .onSubmit { jumpToTypedPage() }

            Text(controller.pageCount > 0 ? "/ \(controller.pageCount)" : "")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                controller.nextPage()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Sonraki sayfa", "Next page"))
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 3) {
            Button {
                controller.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Uzaklaştır", "Zoom out"))

            Button {
                controller.fitWidth()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Sayfayı sığdır", "Fit the page"))

            Button {
                controller.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Yakınlaştır", "Zoom in"))
        }
    }

    /// Steps between the highlighted search matches, with where you are.
    private var matchStepper: some View {
        HStack(spacing: 3) {
            Button {
                controller.focusMatch(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Önceki eşleşme", "Previous match"))

            Text("\(max(1, controller.currentMatch))/\(controller.matchCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(L.pick("Eşleşmeler", "Matches"))

            Button {
                controller.focusMatch(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Sonraki eşleşme", "Next match"))

            Divider().frame(height: 14)
        }
    }

    private func fileMenu(_ url: URL) -> some View {
        Menu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label(L.showInFinder, systemImage: "folder")
            }

            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(L.pick("Önizleme'de aç", "Open in Preview"), systemImage: "arrow.up.forward.app")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func jumpToTypedPage() {
        let digits = pageField.filter(\.isNumber)
        if let number = Int(digits) {
            controller.go(toPage: number)
        }
        pageField = String(controller.currentPage)
    }

    private func missing(_ url: URL) -> some View {
        ContentUnavailableView {
            Label(L.pick("Dosya yerinde değil", "The file is not there"), systemImage: "questionmark.folder")
        } description: {
            Text(L.pick(
                "Fihrist bu dosyayı okumuştu ama şu an bulunamıyor. Taşınmış ya da silinmiş olabilir.",
                "The index read this file, but it cannot be found now. It may have been moved or deleted."
            ) + "\n" + url.path(percentEncoded: false))
        }
    }

    /// The index stores what a file record stores: relative to the root when
    /// the file sits inside it, absolute otherwise.
    private func resolve(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(filePath: path) }

        guard let root = library.url else { return nil }
        return root.appending(path: path)
    }
}

// MARK: - Reader controller

/// Drives one `PDFView` from the SwiftUI chrome around it: the current page and
/// count it reports back, the page/zoom moves the controls ask for, and the
/// search matches the stepper walks through. Holds the view weakly — the view
/// owns itself; this only commands it.
@MainActor
@Observable
final class PDFReaderController {
    weak var view: PDFView?

    private(set) var pageCount = 0
    private(set) var currentPage = 1

    /// The highlighted search matches, and which one is focused (1-based, 0 for
    /// none). Kept here so the stepper can move between them.
    fileprivate var matches: [PDFSelection] = []
    private(set) var matchCount = 0
    private(set) var currentMatch = 0

    /// Pull the live page and count out of the view. Called when the document
    /// loads and whenever the reader scrolls to another page.
    func syncFromView() {
        guard let view, let document = view.document else {
            pageCount = 0
            return
        }
        pageCount = document.pageCount
        if let page = view.currentPage {
            currentPage = document.index(for: page) + 1
        }
    }

    func go(toPage number: Int) {
        guard let view, let document = view.document, document.pageCount > 0 else { return }
        let clamped = min(max(1, number), document.pageCount)
        if let page = document.page(at: clamped - 1) {
            PDFReaderController.scrollToTop(view, page)
            currentPage = clamped
        }
    }

    func nextPage() {
        guard let view, view.canGoToNextPage else { return }
        view.goToNextPage(nil)
        syncFromView()
    }

    func previousPage() {
        guard let view, view.canGoToPreviousPage else { return }
        view.goToPreviousPage(nil)
        syncFromView()
    }

    func zoomIn() {
        guard let view else { return }
        view.autoScales = false
        view.zoomIn(nil)
    }

    func zoomOut() {
        guard let view else { return }
        view.autoScales = false
        view.zoomOut(nil)
    }

    func fitWidth() {
        view?.autoScales = true
    }

    /// Install the matches a fresh document produced, focusing the one on the
    /// page the reader opened at (or the first), and colour them.
    func setMatches(_ selections: [PDFSelection], focusingPageOf target: PDFPage?) {
        matches = selections
        matchCount = selections.count

        guard !selections.isEmpty else {
            currentMatch = 0
            view?.highlightedSelections = nil
            return
        }

        let focus = selections.firstIndex { target != nil && $0.pages.contains(target!) } ?? 0
        currentMatch = focus + 1
        recolour(focused: focus)
    }

    /// Step `delta` matches on, wrapping round, and bring it into view.
    func focusMatch(_ delta: Int) {
        guard let view, !matches.isEmpty else { return }
        let count = matches.count
        var index = (currentMatch - 1) + delta
        index = ((index % count) + count) % count
        currentMatch = index + 1
        recolour(focused: index)
        PDFReaderController.centre(view, matches[index])
        syncFromView()
    }

    private func recolour(focused: Int) {
        for (offset, match) in matches.enumerated() {
            match.color = offset == focused ? .systemOrange : .systemYellow
        }
        view?.highlightedSelections = matches
    }

    /// Centre a selection in the view rather than pinning it to the top. A
    /// destination point maps to the top of the visible area, so placing it
    /// half a screen above the match leaves the match in the middle.
    static func centre(_ view: PDFView, _ selection: PDFSelection) {
        guard let page = selection.pages.first else { return }
        let pageBounds = page.bounds(for: .mediaBox)
        let scale = view.scaleFactor > 0 ? view.scaleFactor : 1
        let halfView = (view.bounds.height / scale) / 2
        let bounds = selection.bounds(for: page)
        let anchorY = min(pageBounds.maxY, bounds.midY + halfView)
        view.go(to: PDFDestination(page: page, at: CGPoint(x: pageBounds.minX, y: anchorY)))
    }

    static func scrollToTop(_ view: PDFView, _ page: PDFPage) {
        let bounds = page.bounds(for: .mediaBox)
        view.go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY)))
    }
}

// MARK: - The page, with a "look this term up" affordance

/// The slide page itself plus the in-place term lookup: select a word (or
/// right-click a selection) and a popover shows what our own glossary and the
/// OpenStax atlas say about it, without leaving the page you are reading.
private struct SlidePDF: View {
    let url: URL
    let page: Int
    let highlight: String
    let controller: PDFReaderController

    /// The selected text and where it sits on the page, reported up from the
    /// PDF view. The popover anchors to this rect so it opens beside the word.
    @State private var selectedText: String?
    @State private var selectionRect: CGRect?
    @State private var showLookup = false

    var body: some View {
        PDFPageView(
            url: url,
            page: page,
            highlight: highlight,
            controller: controller,
            onSelectionChange: { text, rect in
                // While the popover is open, PDFKit may briefly drop the
                // selection as focus moves; keeping the last term stops the
                // popover from closing under itself.
                if let text, let rect {
                    selectedText = text
                    selectionRect = rect
                } else if !showLookup {
                    selectedText = nil
                    selectionRect = nil
                }
            },
            onContextLookup: { text, rect in
                selectedText = text
                selectionRect = rect
                showLookup = true
            }
        )
        .overlay(alignment: .topLeading) { lookupAnchor }
    }

    /// The little "Ara" pill that appears by the selection, and the popover it
    /// anchors. Both the pill and the right-click item drive `showLookup`.
    @ViewBuilder
    private var lookupAnchor: some View {
        if let rect = selectionRect, let term = selectedText {
            Button {
                showLookup = true
            } label: {
                Label(L.pick("Ara", "Look up"), systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .offset(x: rect.minX, y: rect.maxY + 4)
            .popover(isPresented: $showLookup, arrowEdge: .leading) {
                TermLookupPopover(term: term) { showLookup = false }
            }
        }
    }
}

/// A `PDFView` opened at one page with the searched words marked, reporting the
/// current text selection so the page above can offer a lookup, and bound to a
/// `PDFReaderController` so the chrome can drive it.
private struct PDFPageView: NSViewRepresentable {
    let url: URL
    let page: Int
    let highlight: String
    let controller: PDFReaderController

    var onSelectionChange: (String?, CGRect?) -> Void
    var onContextLookup: (String, CGRect) -> Void

    /// Remembers the last page/word we navigated to, so an unrelated redraw
    /// does not yank the view back and fight the reader's own scrolling. Also
    /// holds the observers so they can be torn down, and the latest selection
    /// callback so the long-lived view always calls the current closure.
    final class Coordinator {
        var lastKey: String?
        var selectionToken: NSObjectProtocol?
        var pageToken: NSObjectProtocol?
        var onSelectionChange: ((String?, CGRect?) -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LookupPDFView {
        let view = LookupPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        controller.view = view

        let coordinator = context.coordinator
        coordinator.selectionToken = NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged,
            object: view,
            queue: .main
        ) { [weak view] _ in
            guard let view else { return }
            coordinator.onSelectionChange?(Self.selectedText(of: view), Self.selectionRect(in: view))
        }
        coordinator.pageToken = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
        ) { [weak controller] _ in
            controller?.syncFromView()
        }

        return view
    }

    static func dismantleNSView(_ view: LookupPDFView, coordinator: Coordinator) {
        if let token = coordinator.selectionToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = coordinator.pageToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func updateNSView(_ view: LookupPDFView, context: Context) {
        controller.view = view
        context.coordinator.onSelectionChange = onSelectionChange
        view.onLookup = { term in
            onContextLookup(term, Self.selectionRect(in: view) ?? .zero)
        }

        // Reloading an unchanged document would throw away the scroll
        // position every time anything else on screen changes.
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.lastKey = nil
        }

        guard let document = view.document,
              let target = document.page(at: max(0, page - 1))
        else { return }

        controller.syncFromView()

        let needle = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = needle.isEmpty
            ? []
            : document.findString(needle, withOptions: [.caseInsensitive, .diacriticInsensitive])

        // Scroll only when the target actually changed.
        let key = "\(url.path(percentEncoded: false))#\(page)#\(needle)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key

        controller.setMatches(found, focusingPageOf: target)
        let focused = found.first(where: { $0.pages.contains(target) })

        // Done on the next run-loop tick so the view is laid out and its scale
        // is known, otherwise the centring maths uses a zero-height view.
        DispatchQueue.main.async {
            if let focused {
                PDFReaderController.centre(view, focused)
            } else {
                PDFReaderController.scrollToTop(view, target)
            }
            controller.syncFromView()
        }
    }

    /// The current selection's text, trimmed and capped so a stray drag over a
    /// whole paragraph does not become the lookup term.
    private static func selectedText(of view: PDFView) -> String? {
        guard let raw = view.currentSelection?.string else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }

    /// Where the selection sits, in the view's own top-left coordinates, so the
    /// SwiftUI overlay can place the pill beside it. PDFKit works bottom-left,
    /// hence the flip.
    private static func selectionRect(in view: PDFView) -> CGRect? {
        guard let selection = view.currentSelection, let page = selection.pages.first else { return nil }
        let bounds = selection.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let inView = view.convert(bounds, from: page)
        let top = view.bounds.height - inView.maxY
        return CGRect(x: inView.minX, y: top, width: inView.width, height: inView.height)
    }
}

/// The thumbnail rail down the side, bound to the same `PDFView` so clicking a
/// thumbnail scrolls the reader to that page.
private struct PDFThumbnailPane: NSViewRepresentable {
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView()
        thumbnails.thumbnailSize = CGSize(width: 110, height: 150)
        thumbnails.backgroundColor = .clear
        thumbnails.pdfView = controller.view
        return thumbnails
    }

    func updateNSView(_ thumbnails: PDFThumbnailView, context: Context) {
        if thumbnails.pdfView !== controller.view {
            thumbnails.pdfView = controller.view
        }
    }
}

/// A `PDFView` that adds a "look this up" item to its right-click menu, so a
/// selected term can be sent to the glossary-and-atlas popover.
private final class LookupPDFView: PDFView {
    var onLookup: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        if let raw = currentSelection?.string {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty {
                let item = NSMenuItem(
                    title: L.pick("Sözlük ve Atlas'ta ara", "Look up in glossary & atlas"),
                    action: #selector(lookUpSelection),
                    keyEquivalent: ""
                )
                item.target = self
                menu.insertItem(.separator(), at: 0)
                menu.insertItem(item, at: 0)
            }
        }

        return menu
    }

    @objc private func lookUpSelection() {
        guard let raw = currentSelection?.string else { return }
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        onLookup?(String(term.prefix(80)))
    }
}

// MARK: - The lookup popover

/// What our slide glossary and the OpenStax atlas say about a selected term,
/// shown in place so studying a slide never has to break stride to look a word
/// up. Reads the same curated glossary the Sözlük screen shows and the same
/// atlas index the Atlas screen does; the buttons hand off to those screens
/// when the reader wants the full entry.
private struct TermLookupPopover: View {
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
                                    .buttonStyle(.link)
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
        .frame(width: 360)
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

#else

// MARK: - iOS uygulama içi okuyucu (PencilKit)

/// iPad'in uygulama içi PDF okuyucusu — spike'ta kanıtlanan yaklaşım.
///
/// Tek-sayfa modunda sayfa ekranı doldurur, üstünde tam-boyut bir Apple Pencil
/// tuvali. Her sayfanın çizimi diske yazılıp geri yüklenir; sayfalar ◀▶ ile
/// çevrilir. (Eşzamanlı parmak-gez + kalem-yaz ergonomisi ve terim arama
/// popover'ı sonraki adımlarda; şimdilik kalem her zaman çizer.)
struct SlidePageDetail: View {
    let selection: SlidePageSelection?

    @Environment(LibraryRoot.self) private var library
    @StateObject private var controller = SlideReaderController()

    var body: some View {
        if let selection, let url = resolve(selection.path) {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                reader(url: url, selection: selection)
            } else {
                missing(url)
            }
        } else {
            SelectionPlaceholder(text: L.pick("Bir sonuç seç.", "Pick a result."))
        }
    }

    private func reader(url: URL, selection: SlidePageSelection) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { controller.prev() } label: { Image(systemName: "chevron.left") }
                    .disabled(!controller.canGoPrev)
                Text(controller.pageLabel).font(.callout).monospacedDigit()
                Button { controller.next() } label: { Image(systemName: "chevron.right") }
                    .disabled(!controller.canGoNext)
                Spacer()
                Label(L.pick("Apple Pencil ile yaz", "Draw with Apple Pencil"), systemImage: "applepencil")
                    .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            SlidePencilReader(url: url, startPage: selection.page, controller: controller)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func missing(_ url: URL) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
            Text(L.pick("Dosya bulunamadı.", "File not found."))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resolve(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(filePath: path) }
        guard let root = library.url else { return nil }
        return root.appending(path: path)
    }
}

/// SwiftUI köprüsü: okuyucu kromunun (sayfa düğmeleri, etiket) tuvali süren
/// koordinatöre erişmesini sağlar.
final class SlideReaderController: ObservableObject {
    weak var coordinator: SlidePencilReader.Coordinator?
    @Published var pageLabel = ""
    @Published var canGoPrev = false
    @Published var canGoNext = false
    func next() { coordinator?.next() }
    func prev() { coordinator?.prev() }
}

/// PDFView (tek sayfa) + üstünde tam-boyut PKCanvasView. Kalem çizer; çizimler
/// sayfaya hizalı ve sayfa-başı kalıcı.
struct SlidePencilReader: UIViewRepresentable {
    let url: URL
    let startPage: Int
    let controller: SlideReaderController

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let coord = context.coordinator

        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = .systemGray5
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.document = PDFDocument(url: url)
            ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
        container.addSubview(pdfView)

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 5)
        canvas.delegate = coord
        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        coord.pdfView = pdfView
        coord.canvas = canvas
        coord.controller = controller
        controller.coordinator = coord

        // Aranan sayfadan başla. İndeksi açıkça takip ediyoruz; `currentPage`
        // `go(to:)` sonrası hemen güncellenmediği için ona güvenmiyoruz —
        // kapat-aç'ta kaydın geri yüklenmesini garantileyen şey bu.
        coord.start(at: max(0, startPage - 1))

        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            coord.toolPicker.setVisible(true, forFirstResponder: canvas)
            coord.toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// Okuyucu kapanırken: son çizimi kaydet ve **araç paletini kapat** — yoksa
    /// palet okuyucudan sonra da uygulamada asılı kalıyor.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.finish()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let url: URL
        weak var pdfView: PDFView?
        weak var canvas: PKCanvasView?
        weak var controller: SlideReaderController?
        let toolPicker = PKToolPicker()

        /// Gösterilen sayfanın indeksi — açıkça tutuluyor (PDFView.currentPage'in
        /// zamanlamasına güvenmemek için).
        private var index = 0

        /// Bir çizimi programla yüklerken true. PencilKit, `canvas.drawing`'i
        /// elle set edince de `canvasViewDrawingDidChange` çağırıyor; bu bayrak
        /// o yüklemenin yanlışlıkla (hatta yanlış sayfaya) kaydedilmesini önler.
        private var suppressSave = false

        init(url: URL) {
            self.url = url
            super.init()
            try? FileManager.default.createDirectory(at: Self.dir(url), withIntermediateDirectories: true)
        }

        private var pageCount: Int { pdfView?.document?.pageCount ?? 0 }

        func start(at i: Int) {
            index = min(max(0, i), max(0, pageCount - 1))
            goToIndex()
            showDrawing(index)
            publishState()
        }

        func next() {
            saveCurrent()
            index = min(index + 1, max(0, pageCount - 1))
            goToIndex()
            showDrawing(index)
            publishState()
        }

        func prev() {
            saveCurrent()
            index = max(index - 1, 0)
            goToIndex()
            showDrawing(index)
            publishState()
        }

        /// Sayfanın kayıtlı çizimini yükler; yükleme sırasında kaydı bastırır
        /// (sync ve async didChange'i de kapsasın diye bayrağı sonraki döngüde
        /// sıfırlar).
        private func showDrawing(_ i: Int) {
            suppressSave = true
            canvas?.drawing = load(i)
            DispatchQueue.main.async { [weak self] in self?.suppressSave = false }
        }

        private func goToIndex() {
            if let doc = pdfView?.document, let page = doc.page(at: index) {
                pdfView?.go(to: page)
            }
        }

        /// Kapanış: kaydet + paleti gizle + first responder'ı bırak.
        func finish() {
            saveCurrent()
            if let canvas {
                toolPicker.setVisible(false, forFirstResponder: canvas)
                toolPicker.removeObserver(canvas)
                canvas.resignFirstResponder()
            }
        }

        func publishState() {
            controller?.pageLabel = "\(index + 1) / \(pageCount)"
            controller?.canGoPrev = index > 0
            controller?.canGoNext = index + 1 < pageCount
        }

        func saveCurrent() {
            guard let canvas else { return }
            save(canvas.drawing, index)
        }
        func canvasViewDrawingDidChange(_ cv: PKCanvasView) {
            guard !suppressSave else { return }
            save(cv.drawing, index)
        }

        // Kalıcılık — her (dosya, sayfa) için bir .drawing dosyası.
        // "Ink" klasörü (eski "Drawings" değil): önceki hatalı sürümlerden kalan
        // bozuk çizimlerin yüklenmemesi için temiz bir ad.
        private static func dir(_ url: URL) -> URL {
            URL.documentsDirectory
                .appending(path: "Ink", directoryHint: .isDirectory)
                .appending(path: url.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        }
        private func fileURL(_ i: Int) -> URL { Self.dir(url).appending(path: "\(i).drawing") }
        private func load(_ i: Int) -> PKDrawing {
            (try? Data(contentsOf: fileURL(i))).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        }
        private func save(_ d: PKDrawing, _ i: Int) {
            try? d.dataRepresentation().write(to: fileURL(i))
        }
    }
}

#endif
