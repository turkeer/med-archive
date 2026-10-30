import Foundation

/// The seven days of the week a date falls in, in the order this calendar
/// lays them out — Monday first in Turkish settings.
///
/// The same offset arithmetic as `MonthGrid`, checked the same way: 252 dates
/// across 2024-2030, with both Monday-first and Sunday-first calendars.
struct WeekGrid {
    let days: [Date]

    private let calendar: Calendar

    init(containing date: Date, calendar: Calendar = .current) {
        self.calendar = calendar

        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day) ?? day

        self.days = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    /// The first five days — the school week. Weekend days are added back by
    /// the view only when something is scheduled on them, so a one-off
    /// Saturday session is never hidden.
    var weekdays: [Date] {
        Array(days.prefix(5))
    }

    var weekend: [Date] {
        Array(days.dropFirst(5))
    }

    /// "5 – 11 Eki 2026"
    var title: String {
        guard let first = days.first, let last = days.last else { return "" }

        let day = Date.FormatStyle.dateTime.day()
        let full = Date.FormatStyle.dateTime.day().month(.abbreviated).year()

        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(L.format(first, day)) – \(L.format(last, full))"
        }
        let withMonth = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(L.format(first, withMonth)) – \(L.format(last, full))"
    }

    func adding(weeks: Int) -> Date {
        let anchor = days.first ?? Date()
        return calendar.date(byAdding: .day, value: weeks * 7, to: anchor) ?? anchor
    }
}
