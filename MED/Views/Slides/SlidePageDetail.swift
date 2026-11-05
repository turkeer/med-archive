import AppKit
import PDFKit
import SwiftUI

/// The page a slide hit points at, shown where the chosen record normally is.
///
/// Quick Look and "open in the default app" can both show the file, and
/// neither can open it *at a page* — which is the one thing a page-level
/// search has to be able to do. So the page is drawn here, with the matches
/// marked on it.
struct SlidePageDetail: View {
    let selection: SlidePageSelection?

    @Environment(LibraryRoot.self) private var library

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
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(L.pick("sayfa \(selection.page)", "page \(selection.page)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(L.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)

                Button(L.pick("Önizleme'de aç", "Open in Preview")) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            PDFPageView(url: url, page: selection.page, highlight: selection.query)
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
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

/// A `PDFView` opened at one page with the searched words marked.
private struct PDFPageView: NSViewRepresentable {
    let url: URL
    let page: Int
    let highlight: String

    /// Remembers the last page/word we navigated to, so an unrelated redraw
    /// does not yank the view back and fight the reader's own scrolling. Only
    /// a genuine change of target scrolls.
    final class Coordinator {
        var lastKey: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        // Reloading an unchanged document would throw away the scroll
        // position every time anything else on screen changes.
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.lastKey = nil
        }

        guard let document = view.document,
              let target = document.page(at: max(0, page - 1))
        else { return }

        let needle = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = needle.isEmpty
            ? []
            : document.findString(needle, withOptions: [.caseInsensitive, .diacriticInsensitive])

        for selection in found {
            selection.color = .systemYellow
        }
        view.highlightedSelections = found.isEmpty ? nil : found

        // Scroll only when the target actually changed.
        let key = "\(url.path(percentEncoded: false))#\(page)#\(needle)"
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key

        let onPage = found.first(where: { $0.pages.contains(target) })

        // Centre the match (or the page) in the view rather than pinning it to
        // the top. A destination point maps to the top of the visible area, so
        // placing it half a screen above the match leaves the match in the
        // middle — no more scrolling up by hand to read it. Done on the next
        // run-loop tick so the view is laid out and its scale is known.
        DispatchQueue.main.async {
            let pageBounds = target.bounds(for: .mediaBox)
            let scale = view.scaleFactor > 0 ? view.scaleFactor : 1
            let halfView = (view.bounds.height / scale) / 2

            let anchorY: CGFloat
            if let onPage {
                let bounds = onPage.bounds(for: target)
                anchorY = min(pageBounds.maxY, bounds.midY + halfView)
            } else {
                anchorY = pageBounds.maxY
            }

            view.go(to: PDFDestination(page: target, at: CGPoint(x: pageBounds.minX, y: anchorY)))
        }
    }
}
