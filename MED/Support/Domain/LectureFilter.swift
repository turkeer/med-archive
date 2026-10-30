import Foundation
import SwiftData

/// Which of the archive's sessions the Konular screen is showing.
///
/// Deliberately not remembered across launches, unlike the sort order. A sort
/// order is a preference you set once; a filter is a question you are asking
/// right now. Reopening the app to a filtered subset with no memory of having
/// asked for it reads as data loss — you would think the sessions were gone.
///
/// Each field is a single choice rather than a set. "Anatomi or Biyokimya" is
/// not a question worth the extra interface; "Anatomi" is what you actually
/// ask, and the fields combine with each other anyway.
struct LectureFilter {
    var courseID: PersistentIdentifier?
    var instructorID: PersistentIdentifier?
    var committeeID: PersistentIdentifier?
    var format: LectureFormat?

    /// Only the topics with nothing attached — the list of slides still to be
    /// tracked down, which is the whole point of knowing what is missing.
    var missingFilesOnly = false

    var isActive: Bool {
        courseID != nil
            || instructorID != nil
            || committeeID != nil
            || format != nil
            || missingFilesOnly
    }

    /// `lackingFiles` comes from `LectureGrouping.lacksFiles(among:)` over the
    /// **whole** archive, so that a topic does not count as missing its files
    /// because the part carrying them is itself filtered out. It is a
    /// parameter rather than something computed here because grouping the
    /// archive once per list is cheap and once per row is not.
    func matches(_ lecture: Lecture, lackingFiles: Set<PersistentIdentifier>) -> Bool {
        if let courseID, lecture.course?.persistentModelID != courseID {
            return false
        }

        if let instructorID, lecture.instructor?.persistentModelID != instructorID {
            return false
        }

        if let committeeID, lecture.committee?.persistentModelID != committeeID {
            return false
        }

        if let format, lecture.format != format {
            return false
        }

        if missingFilesOnly, !lackingFiles.contains(lecture.persistentModelID) {
            return false
        }

        return true
    }
}
