import Foundation
import SwiftData

/// What a file is, for grouping on the lecture detail screen.
enum LectureFileKind: String, Codable, CaseIterable, Identifiable {
    /// The file the instructor handed out.
    case slide
    /// A note of your own, e.g. exported from Goodnotes.
    case note
    case other

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .slide: return "Slaytlar"
        case .note:  return "Notlarım"
        case .other: return "Diğer"
        }
    }

    var symbolName: String {
        switch self {
        case .slide: return "doc.richtext"
        case .note:  return "pencil.and.outline"
        case .other: return "doc"
        }
    }
}

/// A pointer to a file on disk. The app never copies or moves the file; it only
/// remembers where it is.
///
/// Two references are kept, deliberately:
///
/// - `relativePath` — the path under the MED root folder. Readable, debuggable,
///   and survives the app's own database being rebuilt.
/// - `bookmarkData` — a macOS bookmark. Only needed when the app runs sandboxed,
///   or for files picked from outside the root folder. `nil` otherwise.
@Model
final class LectureFile {
    var fileName: String = ""

    /// Where the file is. Relative to the library root when it sits inside it —
    /// "Komite I/Biyofizik/2026-10-01 | Basic Principles.pdf" — which survives
    /// the root folder being moved or renamed. Absolute when the file was
    /// picked from somewhere else. Empty when nothing is known.
    var relativePath: String = ""

    /// Security-scoped bookmark, when one is needed. See the type comment.
    var bookmarkData: Data?

    var kind: LectureFileKind = LectureFileKind.slide
    var addedAt: Date = Date()

    /// Inverse is declared on `Lecture.files`, with a cascade delete rule.
    ///
    /// A file record belongs to a lecture **or** to a past paper; whichever
    /// created it sets its side and the other stays nil. Sharing one record
    /// type means both get the same path handling, preview and "never copies
    /// anything" guarantee rather than a second near-identical entity.
    var lecture: Lecture?

    /// Inverse is declared on `PastExam.files`, with a cascade delete rule.
    var exam: PastExam?

    init(
        fileName: String = "",
        relativePath: String = "",
        bookmarkData: Data? = nil,
        kind: LectureFileKind = .slide,
        lecture: Lecture? = nil
    ) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.bookmarkData = bookmarkData
        self.kind = kind
        self.addedAt = Date()
        self.lecture = lecture
    }
}

extension LectureFile {
    /// Resolves to a file on disk, or `nil` when there is nothing to resolve.
    /// Whether the file is actually there is a separate question — the caller
    /// checks, because a file can be moved out from under us at any time.
    func url(root: URL?) -> URL? {
        guard !relativePath.isEmpty else { return nil }

        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }

        guard let root else { return nil }
        return root.appending(path: relativePath)
    }
}
