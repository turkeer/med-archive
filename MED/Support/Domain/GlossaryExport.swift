import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Turns the curated glossary into a document you can keep — Markdown for
/// editing or sharing, PDF for printing or reading. Pure given its input (the
/// terms already cased and grouped by the view), so the Markdown shape is
/// unit-tested; the PDF is a straight typeset of the same content.
enum GlossaryExport {
    /// One definition of a term and the slides it came from.
    struct Definition {
        let text: String
        let sources: [String]
    }

    /// One glossary entry: a term and its definition(s), in display order.
    struct Item {
        let term: String
        let definitions: [Definition]
    }

    /// The letter a term files under in the A–Z layout; non-letters bucket
    /// under "#".
    static func letterKey(_ term: String) -> String {
        guard let first = term.uppercased().first else { return "#" }
        return first.isLetter ? String(first) : "#"
    }

    // MARK: Markdown

    static func markdown(_ items: [Item]) -> String {
        let definitionCount = items.reduce(0) { $0 + $1.definitions.count }
        var out = "# Sözlük\n\n"
        out += "**\(items.count) terim · \(definitionCount) tanım**\n\n"

        var lastLetter = ""
        for item in items {
            let letter = letterKey(item.term)
            if letter != lastLetter {
                out += "## \(letter)\n\n"
                lastLetter = letter
            }
            out += "### \(item.term)\n\n"
            for definition in item.definitions {
                out += definition.text + "\n\n"
                if !definition.sources.isEmpty {
                    out += "_" + definition.sources.joined(separator: " · ") + "_\n\n"
                }
            }
        }
        return out
    }

    #if canImport(AppKit)
    // MARK: PDF

    /// A4 points and a comfortable margin.
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 48

    static func pdf(_ items: [Item]) -> Data {
        pdf(from: attributed(items))
    }

    /// The same content as the Markdown, typeset: a title, per-letter headers,
    /// bold terms, body definitions, and small grey source lines.
    static func attributed(_ items: [Item]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let definitionCount = items.reduce(0) { $0 + $1.definitions.count }

        result.append(line("Sözlük", font: .boldSystemFont(ofSize: 24), spacingAfter: 4))
        result.append(line("\(items.count) terim · \(definitionCount) tanım",
                           font: .systemFont(ofSize: 11), color: Self.meta, spacingAfter: 16))

        var lastLetter = ""
        for item in items {
            let letter = letterKey(item.term)
            if letter != lastLetter {
                result.append(line(letter, font: .boldSystemFont(ofSize: 15),
                                   color: Self.header, spacingBefore: 10, spacingAfter: 4))
                lastLetter = letter
            }
            result.append(line(item.term, font: .boldSystemFont(ofSize: 13), spacingBefore: 6, spacingAfter: 2))
            for definition in item.definitions {
                result.append(line(definition.text, font: .systemFont(ofSize: 11), spacingAfter: 2))
                if !definition.sources.isEmpty {
                    result.append(line(definition.sources.joined(separator: " · "),
                                       font: .systemFont(ofSize: 9), color: Self.meta, spacingAfter: 4))
                }
            }
        }
        return result
    }

    // Fixed, appearance-independent colours. The semantic ones (labelColor …)
    // resolve to WHITE in dark mode, which on a white page is invisible — the
    // whole point of exporting is a document that reads the same everywhere.
    private static let body = NSColor.black
    private static let meta = NSColor(white: 0.40, alpha: 1)
    private static let header = NSColor(white: 0.55, alpha: 1)

    private static func line(_ text: String, font: NSFont, color: NSColor = GlossaryExport.body,
                             spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacingAfter
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text + "\n", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    /// Paginates an attributed string into a PDF with Core Text — no web view,
    /// no print dialog, just the typeset pages.
    static func pdf(from attributed: NSAttributedString) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        let textRect = CGRect(x: margin, y: margin,
                              width: pageSize.width - 2 * margin,
                              height: pageSize.height - 2 * margin)
        let path = CGPath(rect: textRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        var start = 0
        let total = attributed.length
        while start < total {
            context.beginPDFPage(nil)
            // No coordinate flip: Core Text lays a frame out from the top of the
            // path down, and a PDF context already has the upright (y-up) origin
            // it expects, so the text reads correctly as-is. Flipping it here is
            // exactly what turned the pages upside down and all but empty.
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, context)

            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            if visible.length == 0 { break } // nothing fit — avoid an endless loop
            start += visible.length
        }

        context.closePDF()
        return data as Data
    }
    #endif
}
