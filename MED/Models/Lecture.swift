import Foundation
import SwiftData

/// A single lecture: the centre of the data model. Everything else hangs off it.
@Model
final class Lecture {
    var title: String = ""

    /// The calendar day of the lecture, normalised to the start of the day.
    /// Times of day live in `startMinutes` / `endMinutes`, never here.
    var date: Date = Date()

    /// Start time as minutes since midnight (09:30 -> 570). `nil` means unknown.
    /// Stored as minutes rather than a `Date` so that moving a lecture to another
    /// day cannot desynchronise the time, and so sorting is time-zone proof.
    var startMinutes: Int?

    /// End time as minutes since midnight. `nil` means unknown.
    var endMinutes: Int?

    var notes: String = ""
    var createdAt: Date = Date()

    // MARK: Relationships

    /// Deleting an instructor nullifies this (see `Instructor.lectures`).
    var instructor: Instructor?

    /// Deleting a committee nullifies this (see `Committee.lectures`).
    var committee: Committee?

    /// Many-to-many. The inverse is declared here, so `Tag.lectures` stays plain.
    @Relationship(inverse: \Tag.lectures)
    var tags: [Tag] = []

    /// Deleting a lecture deletes its file records. The files on disk are untouched.
    @Relationship(deleteRule: .cascade, inverse: \LectureFile.lecture)
    var files: [LectureFile] = []

    init(
        title: String = "",
        date: Date = Date(),
        startMinutes: Int? = nil,
        endMinutes: Int? = nil,
        notes: String = "",
        instructor: Instructor? = nil,
        committee: Committee? = nil,
        tags: [Tag] = []
    ) {
        self.title = title
        self.date = Calendar.current.startOfDay(for: date)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.notes = notes
        self.createdAt = Date()
        self.instructor = instructor
        self.committee = committee
        self.tags = tags
    }
}

extension Lecture {
    /// Files grouped under the headings the detail screen uses.
    func files(of kind: LectureFileKind) -> [LectureFile] {
        files.filter { $0.kind == kind }.sorted { $0.fileName < $1.fileName }
    }

    var timeRangeText: String {
        TimeOfDay.rangeText(start: startMinutes, end: endMinutes)
    }
}
