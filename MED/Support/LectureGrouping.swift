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

    /// Which way a list of lectures reads.
    enum Order {
        /// Reverse chronological all the way down: the newest day first, and
        /// within a day the **latest** period first. Mixing the two
        /// directions — newest day but earliest period — reads as a mistake,
        /// because on any given day the most recent lesson is the last one.
        case newestFirst

        /// A single day read as a timetable: earliest period first. Used where
        /// the whole list is one day, so there is no date axis to agree with.
        case timetable
    }

    /// Lectures folded into topics.
    ///
    /// Inside a group the parts stay in period order whichever way the list
    /// reads, so part (1) is always the earlier lesson.
    static func groups(of lectures: [Lecture], order: Order = .newestFirst) -> [LectureGroup] {
        let buckets = Dictionary(grouping: lectures) { key(for: $0) }
            .values
            .map { bucket in
                LectureGroup(
                    lectures: bucket.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
                )
            }

        return buckets.sorted { one, other in
            let left = one.first
            let right = other.first

            switch order {
            case .newestFirst:
                if left.date != right.date { return left.date > right.date }
                return (left.startMinutes ?? 0) > (right.startMinutes ?? 0)
            case .timetable:
                if left.date != right.date { return left.date < right.date }
                return (left.startMinutes ?? 0) < (right.startMinutes ?? 0)
            }
        }
    }

    /// The lectures that are parts of the same topic as this one, itself
    /// included, in period order.
    static func parts(of lecture: Lecture, among lectures: [Lecture]) -> [Lecture] {
        let target = key(for: lecture)
        return lectures
            .filter { key(for: $0) == target }
            .sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
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
