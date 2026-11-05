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
/// on the same subject.
///
/// Grouping joins two relations, transitively (see `components`):
///
/// - **Derived, same day.** Two lectures sharing a day, course, topic and
///   format are the same lesson continued after the break — which is exactly
///   what filling down produces, needs nothing stored, and groups two by-hand
///   entries of the same topic just the same. Its one cost, that renaming one
///   part separates it, is arguably the right answer.
/// - **Explicit link, any day.** A subject that runs over several days cannot
///   be derived from the title alone — a generic name like "Anatomy lab"
///   repeats on unrelated days — so the user links those parts by hand and
///   they carry a shared `topicLinkID`.
///
/// This is a different thing from a lecture that *spans* several periods. A
/// span is one record and reads as one tall block in the week grid; parts are
/// separate records and read as separate blocks numbered (1), (2).
enum LectureGrouping {
    /// The same-day rule's key: one subject continued after the break sits on
    /// the same day, course, topic and format.
    private struct DerivedKey: Hashable {
        let day: Date
        let course: PersistentIdentifier?
        let topic: String
        let format: LectureFormat
    }

    /// The same-day key, or `nil` for a lecture that must stand alone: one with
    /// no topic of its own never groups by the derived rule, because two
    /// untitled sessions in the same course on the same day are no evidence of
    /// one subject. An explicit link can still pull such a lecture in.
    private static func derivedKey(for lecture: Lecture) -> DerivedKey? {
        let topic = SearchText.fold(lecture.title)
        guard !topic.isEmpty else { return nil }

        return DerivedKey(
            day: Calendar.current.startOfDay(for: lecture.date),
            course: lecture.course?.persistentModelID,
            topic: topic,
            format: lecture.format
        )
    }

    /// Topics as connected components over two relations: the same-day derived
    /// key, and a shared explicit link id (`Lecture.topicLinkID`).
    ///
    /// Two lectures are parts of one topic when a chain of either relation
    /// joins them. Taking both together, transitively, is what keeps a
    /// same-day pair whole when one of its lessons is linked to another day —
    /// the pair stays bonded by the derived rule while the link reaches across
    /// — instead of the link peeling one lesson off. It also means a link made
    /// to a single lesson of a pair still gathers all three.
    private static func components(of lectures: [Lecture]) -> [[Lecture]] {
        var parent = Array(0 ..< lectures.count)

        func root(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var cur = x
            while parent[cur] != r { let next = parent[cur]; parent[cur] = r; cur = next }
            return r
        }

        func merge(_ a: Int, _ b: Int) { parent[root(a)] = root(b) }

        var firstByDerived: [DerivedKey: Int] = [:]
        var firstByLink: [UUID: Int] = [:]

        for (index, lecture) in lectures.enumerated() {
            if let dkey = derivedKey(for: lecture) {
                if let seen = firstByDerived[dkey] { merge(index, seen) }
                else { firstByDerived[dkey] = index }
            }
            if let link = lecture.topicLinkID {
                if let seen = firstByLink[link] { merge(index, seen) }
                else { firstByLink[link] = index }
            }
        }

        var byRoot: [Int: [Lecture]] = [:]
        for (index, lecture) in lectures.enumerated() {
            byRoot[root(index), default: []].append(lecture)
        }

        return Array(byRoot.values)
    }

    /// Reading order within a topic: by day, then by period. A same-day group
    /// is ordered exactly as before; a cross-day topic reads part (1) as the
    /// earliest day's lesson.
    private static func chronological(_ left: Lecture, _ right: Lecture) -> Bool {
        if left.date != right.date { return left.date < right.date }
        return (left.startMinutes ?? 0) < (right.startMinutes ?? 0)
    }

    /// Lectures folded into topics.
    ///
    /// Inside a group the parts stay in period order whichever way the list
    /// reads, so part (1) is always the earlier lesson.
    static func groups(of lectures: [Lecture], sort: LectureSort = .newestFirst) -> [LectureGroup] {
        components(of: lectures)
            .map { LectureGroup(lectures: $0.sorted(by: chronological)) }
            .sorted { sort.precedes($0.first, $1.first) }
    }

    /// The lectures that are parts of the same topic as this one, itself
    /// included, in reading order.
    static func parts(of lecture: Lecture, among lectures: [Lecture]) -> [Lecture] {
        let id = lecture.persistentModelID
        return components(of: lectures)
            .first { group in group.contains { $0.persistentModelID == id } }?
            .sorted(by: chronological)
            ?? [lecture]
    }

    /// Links `other`'s day into `lecture`'s topic across the calendar.
    ///
    /// The two records touched take a shared id, which is all the explicit
    /// relation needs — each side's same-day siblings ride along through the
    /// derived relation, so a link to one lesson of a pair gathers the pair.
    /// An id already in either topic is reused and spread over the merged set,
    /// so joining two multi-day topics keeps them one.
    static func link(_ lecture: Lecture, with other: Lecture, among lectures: [Lecture]) {
        let merged = parts(of: lecture, among: lectures) + parts(of: other, among: lectures)
        let shared = merged.compactMap(\.topicLinkID).first ?? UUID()

        // Re-stamp anything that already carried a link id, so merging two
        // explicit topics does not leave half of one on the old id; same-day
        // siblings that never had an id keep none and stay bonded by day.
        for part in merged where part.topicLinkID != nil {
            part.topicLinkID = shared
        }

        lecture.topicLinkID = shared
        other.topicLinkID = shared
    }

    /// Detaches a whole day from a topic — every one of that topic's lessons
    /// on `member`'s day loses the link. A day is the unit because its lessons
    /// are bonded to each other by the same-day rule anyway; clearing one would
    /// leave it in the topic through its sibling.
    ///
    /// What is left keeps the link only while it still spans more than one day;
    /// a topic fallen back to a single day needs no link id and is cleared, so
    /// it reverts cleanly to the derived rule.
    static func detachDay(of member: Lecture, among lectures: [Lecture]) {
        let topic = parts(of: member, among: lectures)
        let day = Calendar.current.startOfDay(for: member.date)

        for part in topic where Calendar.current.isDate(part.date, inSameDayAs: day) {
            part.topicLinkID = nil
        }

        let remaining = topic.filter { !Calendar.current.isDate($0.date, inSameDayAs: day) }
        let remainingDays = Set(remaining.map { Calendar.current.startOfDay(for: $0.date) })
        if remainingDays.count <= 1 {
            for part in remaining { part.topicLinkID = nil }
        }
    }

    /// The lectures whose topic has no file attached to any of its parts.
    ///
    /// Topic-wide, not per record, because the parts of one topic share their
    /// files: part (2) is not missing its slides when part (1) is carrying
    /// them. Built in one pass, as a set, so filtering a list does not group
    /// the archive again for every row.
    static func lacksFiles(among lectures: [Lecture]) -> Set<PersistentIdentifier> {
        var result: Set<PersistentIdentifier> = []

        for group in groups(of: lectures)
        where group.lectures.allSatisfy({ $0.files.isEmpty }) && !slidesWaived(group.lectures) {
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

    /// Whether a topic counts as studied: marked on any one of its parts, since
    /// the parts share their study state the way they share their slides.
    static func isStudied(_ lectures: [Lecture]) -> Bool {
        lectures.contains { $0.studiedAt != nil }
    }

    /// Marks or unmarks a whole topic studied, stamping every part so a subject
    /// taught over several periods or days is one tick, not several. Clearing
    /// sets them all back to `nil`.
    static func setStudied(_ studied: Bool, for lectures: [Lecture]) {
        let stamp: Date? = studied ? Date() : nil
        for lecture in lectures { lecture.studiedAt = stamp }
    }

    /// Whether a topic has been marked as having no slides to add: set on any
    /// one of its parts, since the parts share it the way they share slides.
    static func slidesWaived(_ lectures: [Lecture]) -> Bool {
        lectures.contains { $0.slidesWaivedAt != nil }
    }

    /// Marks or unmarks a whole topic as having no slides, stamping every part
    /// so a subject taught over several periods is one decision, not several.
    static func setSlidesWaived(_ waived: Bool, for lectures: [Lecture]) {
        let stamp: Date? = waived ? Date() : nil
        for lecture in lectures { lecture.slidesWaivedAt = stamp }
    }

    /// Whether a topic's slides are accounted for: a file is attached to one of
    /// its parts, or it has been marked as having none to add. This is the test
    /// behind the coverage counts and the "behind" and "missing slides" flags —
    /// not the paperclip glyphs, which mean an actual attached file.
    static func slidesAccountedFor(_ lectures: [Lecture]) -> Bool {
        lectures.contains { !$0.files.isEmpty } || slidesWaived(lectures)
    }

    /// How many lessons (timetable periods) a set of lectures occupies in all.
    ///
    /// Counted in periods, not records: a lesson entered as a single block
    /// spanning two periods ("2.–3. ders") is two lessons, the way the school
    /// counts them, so it weighs the same as two separate back-to-back records.
    /// A lecture off the timetable counts as one.
    static func lessonCount(of lectures: [Lecture]) -> Int {
        lectures.reduce(0) { total, lecture in
            let periods = LessonSlot.span(start: lecture.startMinutes, end: lecture.endMinutes).count
            return total + max(1, periods)
        }
    }

    /// "1.–2. ders", "1., 7. ders", or the plain times when the lectures do
    /// not sit on the timetable at all.
    ///
    /// A topic spread over several days names each day — "Pzt 1.–2. · Salı
    /// 1. ders" — because "1. ders" on two days read as one would say the
    /// wrong thing. One day (the common case) is unchanged.
    static func slotLabel(for lectures: [Lecture]) -> String {
        let byDay = Dictionary(grouping: lectures) {
            Calendar.current.startOfDay(for: $0.date)
        }

        guard byDay.count > 1 else {
            return periodLabel(for: lectures)
        }

        return byDay.keys.sorted()
            .map { day in
                let weekday = L.format(day, Date.FormatStyle.dateTime.weekday(.abbreviated))
                return "\(weekday) \(periodLabel(for: byDay[day] ?? []))"
            }
            .joined(separator: " · ")
    }

    /// The period label for lectures that all sit on one day (or none).
    private static func periodLabel(for lectures: [Lecture]) -> String {
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
