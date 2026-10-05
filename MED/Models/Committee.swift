import Foundation
import SwiftData

/// A block of the curriculum ("Komite I"), with a date range and a colour
/// used to mark its days on the calendar.
@Model
final class Committee {
    var name: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()

    /// Six-digit hex, no leading "#". See `Color(hex:)`.
    var colorHex: String = "7E8CE0"

    /// Deleting a committee must not delete its lectures — the field just empties.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.committee)
    var lectures: [Lecture] = []

    init(
        name: String = "",
        startDate: Date = Date(),
        endDate: Date = Date(),
        colorHex: String = "7E8CE0"
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
    }
}

extension Committee {
    /// "1 Eki 2026 – 14 Kas 2026"
    var dateRangeText: String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
    }

    var lecturesByDate: [Lecture] {
        lectures.sorted { $0.date > $1.date }
    }
}
