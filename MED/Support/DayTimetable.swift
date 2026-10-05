import Foundation

/// One vertical run in a day's column of the week grid: either a block of
/// lectures covering one or more periods, or a single free period.
struct DaySegment: Identifiable {
    /// The period the run starts at.
    let slot: LessonSlot

    /// How many periods it covers. Always 1 for a free run.
    let span: Int

    /// Empty for a free run.
    let lectures: [Lecture]

    var id: Int { slot.number }

    var isFree: Bool { lectures.isEmpty }
}

enum DayTimetable {
    /// Lays a day out as runs, so a double period becomes one tall block
    /// rather than two cells that read as separate lessons.
    ///
    /// The spans always add up to nine periods whatever the data, so every
    /// day's column keeps the same height and the rows stay aligned with the
    /// time column. Checked against twelve arrangements, among them a block
    /// clamped at the end of the day, two lectures claiming the same period,
    /// and a double period with another lecture starting inside it.
    static func segments(for lectures: [Lecture]) -> [DaySegment] {
        let slots = LessonSlot.all
        var segments: [DaySegment] = []
        var index = 0

        while index < slots.count {
            let slot = slots[index]
            let starting = lectures.filter { $0.startMinutes == slot.start }

            guard !starting.isEmpty else {
                segments.append(DaySegment(slot: slot, span: 1, lectures: []))
                index += 1
                continue
            }

            var span = starting
                .map { max(1, LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).count) }
                .max() ?? 1
            span = min(span, slots.count - index)

            // A block must not swallow a lecture that starts inside it, or
            // that lecture would vanish from the week.
            if let nextStart = (index + 1 ..< slots.count).first(where: { candidate in
                lectures.contains { $0.startMinutes == slots[candidate].start }
            }) {
                span = min(span, nextStart - index)
            }

            segments.append(
                DaySegment(
                    slot: slot,
                    span: span,
                    lectures: starting.sorted { $0.displayTitle < $1.displayTitle }
                )
            )
            index += span
        }

        return segments
    }
}

extension DaySegment {
    /// The periods this run covers.
    var slots: [LessonSlot] {
        let start = slot.number - 1
        return Array(LessonSlot.all[start ..< min(start + span, LessonSlot.all.count)])
    }

    /// "2. ders", or "2.–3. ders" for a run of several.
    var label: String {
        guard let last = slots.last, last.number != slot.number else { return slot.label }
        return L.lessonRange(slot.number, last.number)
    }

    /// "09:40", or "09:40–11:10" for a run of several.
    var timeText: String {
        guard let last = slots.last, last.number != slot.number else {
            return TimeOfDay.text(slot.start)
        }
        return "\(TimeOfDay.text(slot.start))–\(TimeOfDay.text(last.end))"
    }
}
