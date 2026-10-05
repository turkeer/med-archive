import Foundation

/// A period in the school's fixed weekday timetable.
///
/// Deliberately code, not data. A lecture still stores its real
/// `startMinutes` / `endMinutes`; the slot is *derived* from them. So if the
/// timetable ever changes, you edit the table below and nothing migrates —
/// existing records keep the times they actually had, and simply stop
/// lining up with a slot, which the UI shows as a custom time.
struct LessonSlot: Identifiable, Hashable {
    let number: Int
    /// Minutes since midnight.
    let start: Int
    let end: Int

    var id: Int { number }

    /// "08:50–09:30"
    var timeText: String {
        "\(TimeOfDay.text(start))–\(TimeOfDay.text(end))"
    }

    /// "3. ders"
    var label: String {
        "\(number). ders"
    }

    /// "3. ders · 10:30–11:10"
    var longLabel: String {
        "\(label) · \(timeText)"
    }

    // MARK: The timetable

    static let all: [LessonSlot] = [
        make(1, 8, 50, 9, 30),
        make(2, 9, 40, 10, 20),
        make(3, 10, 30, 11, 10),
        make(4, 11, 20, 12, 0),
        make(5, 12, 10, 12, 50),
        make(6, 13, 50, 14, 30),
        make(7, 14, 40, 15, 20),
        make(8, 15, 30, 16, 10),
        make(9, 16, 20, 17, 0),
    ]

    private static func make(
        _ number: Int,
        _ startHour: Int, _ startMinute: Int,
        _ endHour: Int, _ endMinute: Int
    ) -> LessonSlot {
        LessonSlot(
            number: number,
            start: startHour * 60 + startMinute,
            end: endHour * 60 + endMinute
        )
    }

    // MARK: Deriving slots from times

    /// The slots a time range covers, but only when both ends land exactly on
    /// slot boundaries. An off-grid range returns empty, which is how the UI
    /// tells a timetabled lecture from a one-off.
    static func span(start: Int?, end: Int?) -> [LessonSlot] {
        guard let start, let end, end > start,
              let first = all.first(where: { $0.start == start }),
              let last = all.first(where: { $0.end == end }),
              last.number >= first.number
        else { return [] }

        return all.filter { $0.number >= first.number && $0.number <= last.number }
    }

    /// "3. ders", "1.–2. ders", or `nil` when the range is off the timetable.
    static func spanLabel(start: Int?, end: Int?) -> String? {
        let slots = span(start: start, end: end)
        guard let first = slots.first, let last = slots.last else { return nil }
        return first.number == last.number
            ? "\(first.number). ders"
            : "\(first.number).–\(last.number). ders"
    }

    /// The range starting at this slot and running for `count` slots, clamped
    /// to the end of the day.
    func range(lasting count: Int) -> (start: Int, end: Int) {
        let lastIndex = min(number - 1 + max(1, count) - 1, Self.all.count - 1)
        return (start, Self.all[lastIndex].end)
    }

    /// True when a lecture occupying `start..<end` takes up any of this slot.
    /// A lecture with a start but no end is treated as one slot long.
    func overlaps(start: Int?, end: Int?) -> Bool {
        guard let start else { return false }
        let finish = end ?? (start + 40)
        return start < self.end && finish > self.start
    }
}
