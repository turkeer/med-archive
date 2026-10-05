import Foundation
import SwiftData

/// Several lectures that are parts of one topic.
struct LectureGroup: Identifiable {
    /// At least one lecture, in period order.
    let lectures: [Lecture]

    var id: PersistentIdentifier { lectures[0].persistentModelID }
    var first: Lecture { lectures[0] }
    var count: Int { lectures.count }
}

/// Parts of one topic: separate lessons the school counts separately, taught
/// back to back on the same subject with a break between them.
///
/// Derived, never stored. Two lectures are parts of the same topic when they
/// share a day, a course, a topic and a format — which is what "the same
/// lesson, continued after the break" means, and exactly what filling down
/// produces. Nothing to migrate, nothing to keep in sync, and writing the same
/// topic twice by hand groups them just the same. The one cost: renaming one
/// part separates it, which is arguably the right answer anyway.
///
/// This is a different thing from a lecture that *spans* several periods. A
/// span is one record and reads as one tall block in the week grid; parts are
/// separate records and read as separate blocks numbered (1), (2).
enum LectureGrouping {
    private struct Key: Hashable {
        let day: Date
        let course: PersistentIdentifier?
        let topic: String
        let format: LectureFormat

        /// Set for lectures that must never group, which keeps them in
        /// buckets of their own.
        let alone: PersistentIdentifier?
    }

    /// A lecture with no topic of its own never groups: two untitled sessions
    /// in the same course on the same day are no evidence of one subject.
    private static func key(for lecture: Lecture) -> Key {
        let topic = SearchText.fold(lecture.title)

        return Key(
            day: Calendar.current.startOfDay(for: lecture.date),
            course: lecture.course?.persistentModelID,
            topic: topic,
            format: lecture.format,
            alone: topic.isEmpty ? lecture.persistentModelID : nil
        )
    }

    /// Newest day first, and within a day the earliest period first.
    ///
    /// Both halves matter. Sorting by date alone left same-day lectures in
    /// whatever order they came out of the store, so an afternoon lecture
    /// could sit above a morning one.
    static func inOrder(_ lectures: [Lecture]) -> [Lecture] {
        lectures.sorted { one, other in
            if one.date != other.date { return one.date > other.date }
            return (one.startMinutes ?? 0) < (other.startMinutes ?? 0)
        }
    }

    /// Lectures folded into topics, newest first.
    static func groups(of lectures: [Lecture]) -> [LectureGroup] {
        Dictionary(grouping: lectures) { key(for: $0) }
            .values
            .map { bucket in
                LectureGroup(
                    lectures: bucket.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
                )
            }
            .sorted { one, other in
                if one.first.date != other.first.date { return one.first.date > other.first.date }
                return (one.first.startMinutes ?? 0) < (other.first.startMinutes ?? 0)
            }
    }

    /// Which part each lecture is, for the ones that have siblings. Built in
    /// one pass so a list of rows does not look this up per row.
    static func partNumbers(
        for lectures: [Lecture]
    ) -> [PersistentIdentifier: (index: Int, total: Int)] {
        var result: [PersistentIdentifier: (index: Int, total: Int)] = [:]

        for group in groups(of: lectures) where group.count > 1 {
            for (offset, lecture) in group.lectures.enumerated() {
                result[lecture.persistentModelID] = (offset + 1, group.count)
            }
        }

        return result
    }

    /// "1.–2. ders", "1., 7. ders", or the plain times when the lectures do
    /// not sit on the timetable at all.
    static func slotLabel(for lectures: [Lecture]) -> String {
        let numbers = Set(
            lectures.flatMap {
                LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).map(\.number)
            }
        ).sorted()

        guard let first = numbers.first, let last = numbers.last else {
            let times = lectures.first?.timeRangeText ?? ""
            return times.isEmpty ? "saat yok" : times
        }

        if numbers.count == last - first + 1 {
            return first == last ? "\(first). ders" : "\(first).–\(last). ders"
        }

        return numbers.map(String.init).joined(separator: ", ") + ". ders"
    }
}
