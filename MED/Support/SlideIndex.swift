import CoreGraphics
import Foundation
import Observation
import PDFKit
import Vision

/// The text inside the PDFs under the library root, so that searching can
/// reach what a slide actually says rather than only what its lecture is
/// called.
///
/// Kept on disk beside the store and deliberately **not** inside it. This is
/// derived data: it can be thrown away and rebuilt from the PDFs in a few
/// seconds, so putting it in the archive would mean a schema migration, a
/// bigger backup and a bigger thing to lose, for something that is not
/// archive at all. Delete the folder and it comes back.
///
/// Text is stored a page at a time even though the search currently matches
/// whole files: the page is what you actually want to be sent to, and
/// throwing that away here would mean reading all 2000 pages again later.
@MainActor
@Observable
final class SlideIndex {
    /// One PDF's text, plus what the file looked like when it was read so an
    /// unchanged file is never read twice.
    private struct Entry: Codable, Sendable {
        var size: Int
        var modified: Date
        var pages: [String]

        /// Indexes into `pages` whose text was recognised from the rendered
        /// page rather than read out of the PDF. Kept because OCR can
        /// misread, and a hit that comes from it is worth treating as a
        /// weaker claim than one the file itself spelled out.
        var ocrPages: [Int] = []

        /// Whether the image-reading pass has been over this file. Without it
        /// the second pass cannot tell "nothing to recognise here" from "not
        /// looked at yet", and would start again on every launch.
        var ocrDone: Bool

        /// Pages that have no text even after being looked at as an image.
        var unreadablePages: Int {
            pages.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count < Self.minimumUseful }.count
        }

        /// Below this, a page is treated as having no text worth having.
        static let minimumUseful = 20
    }

    private struct Cache: Codable, Sendable {
        /// Bumped when `Entry` changes shape, so an old file is discarded
        /// rather than decoded into something it is not. 2 added reading from
        /// the image; 3 added the flag that lets that happen in a pass of its
        /// own.
        var version = 3
        var entries: [String: Entry] = [:]
    }

    private var entries: [String: Entry] = [:]

    /// Folded once at build time, not per keystroke: `SearchText.fold` over
    /// 650 KB on every character typed would be felt.
    private var foldedText: [String: String] = [:]

    private(set) var isWorking = false
    private(set) var fileCount = 0
    private(set) var pageCount = 0

    /// Pages whose words were recognised from the image, because the PDF
    /// itself had none to give.
    private(set) var ocrPageCount = 0

    /// Pages with nothing readable even then.
    private(set) var unreadablePageCount = 0

    private(set) var lastBuilt: Date?

    /// Not actor-isolated: the background build writes the file itself.
    private nonisolated static var cacheURL: URL {
        StoreLocation.directory
            .appending(path: "Index", directoryHint: .isDirectory)
            .appending(path: "slides.json")
    }

    init() {
        adopt(Self.read() ?? Cache(), built: nil)
    }

    // MARK: Searching

    /// The stored paths whose slide text contains `query`.
    ///
    /// Returned as a set for the whole query rather than asked per lecture:
    /// one pass over the index per search, not one per row.
    func matchingPaths(query: String) -> Set<String> {
        let needle = SearchText.fold(query)
        guard !needle.isEmpty else { return [] }

        var hits: Set<String> = []
        for (path, text) in foldedText where text.contains(needle) {
            hits.insert(path)
        }

        return hits
    }

    /// Pages of one file that contain `query`, one-based. For telling you
    /// where to look rather than only which file to open.
    func matchingPages(in path: String, query: String) -> [Int] {
        let needle = SearchText.fold(query)
        guard !needle.isEmpty, let entry = entries[path] else { return [] }

        return entry.pages.enumerated()
            .filter { SearchText.contains($0.element, query: needle) }
            .map { $0.offset + 1 }
    }

    /// True when this page's text came from OCR, so a caller can mark a hit
    /// as the weaker kind of match.
    func isRecognised(path: String, page: Int) -> Bool {
        entries[path]?.ocrPages.contains(page - 1) ?? false
    }

    // MARK: Building

    /// Reads whatever has changed under `root`. Safe to call on every launch:
    /// files whose size and date still match are not opened again.
    func refresh(root: URL?) {
        guard !isWorking else { return }

        guard let root, LibraryRoot.exists(at: root) else {
            adopt(Cache(), built: nil)
            Self.write(Cache())
            return
        }

        isWorking = true
        let known = entries

        Task.detached(priority: .utility) {
            // Two passes, because they cost wildly different amounts and only
            // one of them is needed for searching to start working.
            //
            // The text the PDFs already carry comes out in about five seconds.
            // Reading the pages that have no text of their own takes minutes
            // on a first run — and doing both before handing anything over
            // meant a new install had three minutes where searching inside
            // slides silently found nothing at all. Whoever opened it then
            // would have concluded the feature was broken.
            let (text, textChanged) = Self.build(root: root, reusing: known, readingImages: false)
            if textChanged { Self.write(text) }
            await MainActor.run { self.adopt(text, built: Date()) }

            // Rewriting an unchanged index would cost a launch-time write of
            // several hundred kilobytes and, worse, would reset the file's
            // date — the one cheap way of seeing when the index last actually
            // changed.
            let (full, fullChanged) = Self.build(root: root, reusing: text.entries, readingImages: true)
            if fullChanged { Self.write(full) }

            await MainActor.run {
                self.adopt(full, built: Date())
                self.isWorking = false
            }
        }
    }

    /// Walks the root and extracts what is missing or stale.
    ///
    /// Everything under the root is read, not only the files attached to a
    /// lecture: a slide you have not filed yet is exactly the one you cannot
    /// find by any other means.
    private nonisolated static func build(
        root: URL,
        reusing known: [String: Entry],
        readingImages: Bool
    ) -> (cache: Cache, changed: Bool) {
        let manager = FileManager.default
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard let walker = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return (Cache(), !known.isEmpty) }

        var cache = Cache()
        var changed = false

        for case let url as URL in walker where url.pathExtension.lowercased() == "pdf" {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            // The same relative form `LibraryRoot` stores on a file record, so
            // a hit can be matched back to a lecture without re-deriving it.
            let key = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path

            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast

            // Unchanged, and already as complete as this pass can make it.
            // Leaving a file alone here is what makes a later launch cost
            // seconds instead of minutes, and what lets the image pass pick up
            // where it left off if the app was quit halfway through.
            if let seen = known[key], seen.size == size, seen.modified == modified,
               seen.ocrDone || !readingImages {
                cache.entries[key] = seen
                continue
            }

            guard let document = PDFDocument(url: url) else { continue }

            var pages: [String] = []
            var recognised: [Int] = []

            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else {
                    pages.append("")
                    continue
                }

                let embedded = page.string ?? ""
                let hasText = embedded
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .count >= Entry.minimumUseful

                if hasText || !readingImages {
                    pages.append(embedded)
                    continue
                }

                // A page with no text of its own: a scanned slide, or a
                // diagram whose labels only exist in the picture. Both are
                // worth reading — an eighth of this archive's pages are like
                // this, and the words on them are exactly the ones you would
                // search for.
                let read = Self.recognise(page)
                pages.append(read.isEmpty ? embedded : read)
                if !read.isEmpty { recognised.append(index) }
            }

            cache.entries[key] = Entry(
                size: size,
                modified: modified,
                pages: pages,
                ocrPages: recognised,
                ocrDone: readingImages
            )
            changed = true
        }

        // A file that went away is a change too, or a deleted slide would
        // keep answering searches.
        return (cache, changed || cache.entries.count != known.count)
    }

    /// The words on a page, read from the rendered image.
    ///
    /// Drawn at twice the page size: at 1x the body text on a slide comes out
    /// too small to recognise, and beyond 2x it costs memory without reading
    /// any more.
    private nonisolated static func recognise(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return "" }

        // Slides are drawn on white; without this the transparent areas come
        // out black and the text disappears into them.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Off: these are Latin anatomical terms and medical words, and the
        // corrector turns them into ordinary English ones.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "tr-TR"]

        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }

    private func adopt(_ cache: Cache, built: Date?) {
        entries = cache.entries
        foldedText = cache.entries.mapValues { SearchText.fold($0.pages.joined(separator: "\n")) }

        fileCount = cache.entries.count
        pageCount = cache.entries.values.reduce(0) { $0 + $1.pages.count }
        ocrPageCount = cache.entries.values.reduce(0) { $0 + $1.ocrPages.count }
        unreadablePageCount = cache.entries.values.reduce(0) { $0 + $1.unreadablePages }

        if let built { lastBuilt = built }
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
            // An index that cannot be cached still works for this run; it
            // just gets rebuilt next launch.
            print("MED: slayt fihristi yazılamadı — \(error)")
        }
    }
}
