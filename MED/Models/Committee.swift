import Foundation
import SwiftData

/// A block of the curriculum ("Komite I"), with a date range and a colour
/// used to mark its days on the calendar.
@Model
final class Committee {
    /// The real title, e.g. "Introduction to Medicine".
    var name: String = ""

    /// A short label for places where the full title will not fit — a chip, a
    /// list row — e.g. "Komite I". Falls back to `name` when empty.
    var code: String = ""

    var startDate: Date = Date()
    var endDate: Date = Date()

    /// Six-digit hex, no leading "#". See `Color(hex:)`.
    var colorHex: String = "7E8CE0"

    /// Deleting a committee must not delete its lectures — the field just empties.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.committee)
    var lectures: [Lecture] = []

    init(
        name: String = "",
        code: String = "",
        startDate: Date = Date(),
        endDate: Date = Date(),
        colorHex: String = "7E8CE0"
    ) {
        self.name = name
        self.code = code
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
    }
}

extension Committee {
    /// What to show where space is tight.
    var shortLabel: String {
        code.isEmpty ? name : code
    }

    /// "Komite I — Introduction to Medicine", or whichever half exists.
    var fullLabel: String {
        if code.isEmpty { return name }
        if name.isEmpty { return code }
        return "\(code) — \(name)"
    }

    /// True when `day` falls inside this committee's range, days only.
    func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        return calendar.startOfDay(for: startDate) <= target
            && target <= calendar.startOfDay(for: endDate)
    }

    /// "1 Eki 2026 – 14 Kas 2026"
    var dateRangeText: String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
    }

    var lecturesByDate: [Lecture] {
        lectures.sorted { $0.date > $1.date }
    }
}
