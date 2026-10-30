import Foundation
import SwiftData

/// How a list of lectures is ordered.
enum LectureSort: String, CaseIterable, Identifiable {
    /// Reverse chronological all the way down: the newest day first, and
    /// within a day the latest period first. Mixing the two directions —
    /// newest day but earliest period — reads as a mistake, because on any
    /// given day the most recent lesson is the last one.
    case newestFirst

    /// Chronological. Also what a single day read as a timetable wants, so
    /// the day column uses this rather than a separate notion.
    case oldestFirst

    case titleAscending
    case titleDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst:     return L.pick("Yeniden eskiye", "Newest first")
        case .oldestFirst:     return L.pick("Eskiden yeniye", "Oldest first")
        case .titleAscending:  return L.pick("Konu A→Z", "Topic A→Z")
        case .titleDescending: return L.pick("Konu Z→A", "Topic Z→A")
        }
    }
}

extension LectureSort {
    /// Whether `left` comes before `right` in this order.
    ///
    /// Ordering lives here, not in a `SortDescriptor`, because two of the four
    /// orders sort by `displayTitle` — a computed title that falls back to the
    /// course name — which no stored-property descriptor can express. Having
    /// one definition also keeps the ungrouped Konular list and the grouped
    /// lists on the related screens from disagreeing about what "newest" is.
    func precedes(_ left: Lecture, _ right: Lecture) -> Bool {
        switch self {
        case .newestFirst:
            if left.date != right.date { return left.date > right.date }
            return (left.startMinutes ?? 0) > (right.startMinutes ?? 0)

        case .oldestFirst:
            if left.date != right.date { return left.date < right.date }
            return (left.startMinutes ?? 0) < (right.startMinutes ?? 0)

        case .titleAscending, .titleDescending:
            // Collation, not folding: Turkish orders ı before i, and the
            // locale knows that where a flattened comparison would not.
            let comparison = left.displayTitle.localizedStandardCompare(right.displayTitle)
            if comparison != .orderedSame {
                let ascending = comparison == .orderedAscending
                return self == .titleAscending ? ascending : !ascending
            }
            // Same topic on different days: keep it stable and readable.
            return left.date > right.date
        }
    }
}

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

    /// Lectures folded into topics.
    ///
    /// Inside a group the parts stay in period order whichever way the list
    /// reads, so part (1) is always the earlier lesson.
    static func groups(of lectures: [Lecture], sort: LectureSort = .newestFirst) -> [LectureGroup] {
        let buckets = Dictionary(grouping: lectures) { key(for: $0) }
            .values
            .map { bucket in
                LectureGroup(
                    lectures: bucket.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
                )
            }

        return buckets.sorted { sort.precedes($0.first, $1.first) }
    }

    /// The lectures that are parts of the same topic as this one, itself
    /// included, in period order.
    static func parts(of lecture: Lecture, among lectures: [Lecture]) -> [Lecture] {
        let target = key(for: lecture)
        return lectures
            .filter { key(for: $0) == target }
            .sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
    }

    /// The lectures whose topic has no file attached to any of its parts.
    ///
    /// Topic-wide, not per record, because the parts of one topic share their
    /// files: part (2) is not missing its slides when part (1) is carrying
    /// them. Built in one pass, as a set, so filtering a list does not group
    /// the archive again for every row.
    static func lacksFiles(among lectures: [Lecture]) -> Set<PersistentIdentifier> {
        var result: Set<PersistentIdentifier> = []

        for group in groups(of: lectures) where group.lectures.allSatisfy({ $0.files.isEmpty }) {
            for lecture in group.lectures {
                result.insert(lecture.persistentModelID)
            }
        }

        return result
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
            return times.isEmpty ? L.noTime : times
        }

        if numbers.count == last - first + 1 {
            return L.lessonRange(first, last)
        }

        return L.lessonList(numbers)
    }
}
