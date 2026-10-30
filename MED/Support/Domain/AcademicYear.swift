import Foundation

/// Academic years, stored as the calendar year they start in: 2022 means
/// 2022-2023.
///
/// One number rather than a typed-in string. "2022-2023" written by hand
/// invites "2022-23", "2022/2023" and the odd typo, and none of those sort.
enum AcademicYear {
    /// The academic year a date falls in. The Turkish academic year starts in
    /// autumn, so January 2026 belongs to 2025-2026.
    static func startYear(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2025
        let month = parts.month ?? 1
        return month >= 8 ? year : year - 1
    }

    /// "2022-2023"
    static func label(startYear: Int) -> String {
        "\(startYear)-\(startYear + 1)"
    }

    /// The oldest year worth offering. Papers older than this are not around
    /// any more, and a picker full of them is just scrolling.
    static let earliestStartYear = 2018

    /// Years to choose from, newest first, down to `earliestStartYear`.
    ///
    /// `including` keeps a year that is already stored but outside the range
    /// in the list, so an existing record never loses its own value.
    static func choices(including stored: Int? = nil, from date: Date = Date()) -> [Int] {
        let current = startYear(for: date)
        var years = Set(stride(from: current, through: min(earliestStartYear, current), by: -1))

        if let stored {
            years.insert(stored)
        }

        return years.sorted(by: >)
    }
}
