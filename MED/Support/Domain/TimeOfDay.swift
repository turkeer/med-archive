import Foundation

/// Converts between "minutes since midnight" (how lecture times are stored)
/// and the `Date` values SwiftUI's pickers want.
enum TimeOfDay {
    /// Falls back to the first period, so switching a time on by hand lands
    /// somewhere the timetable recognises rather than on an arbitrary 09:00.
    static var defaultStart: Int { LessonSlot.all[0].start }
    static var defaultEnd: Int { LessonSlot.all[0].end }

    /// Minutes since midnight for the time part of `date`.
    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// A `Date` on `day` whose time part is `minutes` since midnight.
    static func date(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// "09:30", or an empty string for `nil`.
    static func text(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "09:30 – 10:20", or one side alone, or an empty string.
    static func rangeText(start: Int?, end: Int?) -> String {
        switch (start, end) {
        case let (start?, end?): return "\(text(start)) – \(text(end))"
        case let (start?, nil):  return text(start)
        case let (nil, end?):    return "– \(text(end))"
        case (nil, nil):         return ""
        }
    }
}
