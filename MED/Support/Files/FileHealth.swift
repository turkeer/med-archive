import Foundation
import SwiftData

/// Which file records no longer point at a file.
///
/// The app stores where a file is, never a copy of it, so a file moved or
/// renamed in Finder leaves a record pointing at nothing. On its own screen
/// that shows as "file not found" on one row, which you only see if you happen
/// to open that lecture — hence a report that answers it for the whole archive
/// at once.
enum FileHealth {
    /// Records whose path resolves to nothing on disk.
    ///
    /// A relative path with no root folder chosen is **not** counted. It
    /// cannot be resolved, which is not the same as being broken, and counting
    /// it would tell you every file in the archive was lost the moment you
    /// cleared the root folder.
    static func broken(among records: [LectureFile], library: LibraryRoot) -> [LectureFile] {
        records.filter { record in
            guard !record.relativePath.isEmpty else { return false }
            guard record.relativePath.hasPrefix("/") || library.url != nil else { return false }
            guard let url = record.url(root: library.url) else { return false }

            return !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    /// What a record belongs to, for a list that mixes lecture files and past
    /// papers.
    static func ownerText(of record: LectureFile) -> String {
        if let lecture = record.lecture {
            return "\(lecture.displayTitle) · \(L.format(lecture.date, Date.FormatStyle.dateTime.day().month(.abbreviated).year()))"
        }
        if let exam = record.exam {
            return exam.title
        }
        return L.pick("Sahibi yok", "No owner")
    }
}
