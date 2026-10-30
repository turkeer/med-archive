import Foundation

/// The 42 cells of a month view: six fixed rows, so the grid keeps its height
/// when you move between months instead of gaining and losing a row.
///
/// Six rows is always enough. The widest case is a 31-day month whose first day
/// sits at the end of the week, which needs 37 cells.
struct MonthGrid {
    /// The first day of the month being shown.
    let month: Date

    /// 42 consecutive days, each the start of its day. Includes the tail of the
    /// previous month and the head of the next one.
    let days: [Date]

    private let calendar: Calendar

    init(containing date: Date, calendar: Calendar = .current) {
        self.calendar = calendar

        let parts = calendar.dateComponents([.year, .month], from: date)
        let startOfMonth = calendar.date(from: parts) ?? calendar.startOfDay(for: date)
        self.month = startOfMonth

        // `weekday` is 1 for Sunday; `firstWeekday` is whatever the user's
        // calendar starts on — 2 (Monday) in Turkish settings.
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: startOfMonth) ?? startOfMonth

        self.days = (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    func isInMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: month, toGranularity: .month)
    }

    /// Weekday headings in the order this calendar lays them out.
    var weekdaySymbols: [String] {
        // Not the calendar's own symbols: those follow the Mac's language,
        // which is the one thing the window is not following any more.
        let formatter = DateFormatter()
        formatter.locale = L.locale
        let symbols = formatter.shortWeekdaySymbols ?? calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    /// "Ekim 2026"
    var title: String {
        L.format(month, Date.FormatStyle.dateTime.month(.wide).year())
    }

    func adding(months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: month) ?? month
    }

    func dayNumber(of day: Date) -> Int {
        calendar.component(.day, from: day)
    }
}
