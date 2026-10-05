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

    /// Path relative to the MED root folder, e.g.
    /// "Komite I/Biyofizik/2026-10-01 | Basic Principles.pdf".
    /// Empty when the file lives outside the root and is only reachable by bookmark.
    var relativePath: String = ""

    /// Security-scoped bookmark, when one is needed. See the type comment.
    var bookmarkData: Data?

    var kind: LectureFileKind = LectureFileKind.slide
    var addedAt: Date = Date()

    /// Inverse is declared on `Lecture.files`, with a cascade delete rule.
    var lecture: Lecture?

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
