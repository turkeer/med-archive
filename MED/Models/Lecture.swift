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

    /// Stored optional, read through `format`, even though every lecture has one.
    ///
    /// SwiftData does not backfill a newly added attribute with its Swift
    /// default: the default applies to records created afterwards, while rows
    /// that already existed keep NULL in the store. Reading NULL into a
    /// non-optional Codable enum crashes with
    /// "Could not cast value of type 'Swift.Optional<Any>'" — which is exactly
    /// what happened when this field was first added as non-optional.
    ///
    /// Plain types like String and Int are fine, because their default can be
    /// written into the store's own metadata. A Codable enum's cannot.
    private var formatRaw: LectureFormat?

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
        self.formatRaw = format
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

    /// Lecture or lab. Records that predate this field read as theoretical,
    /// which is what the great majority of them are.
    var format: LectureFormat {
        get { formatRaw ?? .theoretical }
        set { formatRaw = newValue }
    }

    /// "3. ders · 10:30–11:10" when the times line up with the school's
    /// timetable, otherwise just the times.
    var scheduleText: String {
        guard let label = LessonSlot.spanLabel(start: startMinutes, end: endMinutes) else {
            return timeRangeText
        }
        return "\(label) · \(timeRangeText)"
    }

    /// The colour this lecture is marked with on the month calendar: its
    /// course's, falling back to its committee's.
    ///
    /// The course comes first on purpose. A committee runs for weeks, so
    /// marking by committee paints every day of a month the same colour and
    /// tells you nothing beyond "something is on". Course colours make a day
    /// legible at a glance — Anatomi and Biyofizik today, Histoloji tomorrow —
    /// and match what the week grid already uses.
    var markerColorHex: String? {
        course?.colorHex ?? committee?.colorHex
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
