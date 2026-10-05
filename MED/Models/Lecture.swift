import Foundation
import SwiftData

/// A single lecture: the centre of the data model. Everything else hangs off it.
@Model
final class Lecture {
    /// The topic of this particular session ("Üst ekstremite kasları").
    /// The recurring course it belongs to is `course`.
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

    /// Lecture or lab. Existing records read as theoretical, which is what
    /// the great majority of them are.
    var format: LectureFormat = LectureFormat.theoretical

    var notes: String = ""
    var createdAt: Date = Date()

    // MARK: Relationships

    /// The recurring course this session belongs to (see `Course.lectures`).
    /// Deleting a course nullifies this.
    var course: Course?

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
        format: LectureFormat = .theoretical,
        notes: String = "",
        course: Course? = nil,
        instructor: Instructor? = nil,
        committee: Committee? = nil,
        tags: [Tag] = []
    ) {
        self.title = title
        self.date = Calendar.current.startOfDay(for: date)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.format = format
        self.notes = notes
        self.createdAt = Date()
        self.course = course
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

    /// "3. ders · 10:30–11:10" when the times line up with the school's
    /// timetable, otherwise just the times.
    var scheduleText: String {
        guard let label = LessonSlot.spanLabel(start: startMinutes, end: endMinutes) else {
            return timeRangeText
        }
        return "\(label) · \(timeRangeText)"
    }

    /// The colour this lecture is marked with on the calendar: its committee's,
    /// falling back to its course's. `nil` when it has neither.
    var markerColorHex: String? {
        committee?.colorHex ?? course?.colorHex
    }

    /// True when a topic of its own was written down.
    var hasTopic: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What to show as the heading: the topic, or the course name when there is
    /// no topic ("Anatomi — pratik" style entries), or a last-resort placeholder.
    var displayTitle: String {
        let topic = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty { return topic }
        if let course, !course.name.isEmpty { return course.name }
        return "(başlıksız)"
    }
}
