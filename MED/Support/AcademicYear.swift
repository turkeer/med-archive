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

    /// Years to choose from, newest first: this one and the ones before it.
    static func choices(back years: Int = 15, from date: Date = Date()) -> [Int] {
        let current = startYear(for: date)
        return (0...years).map { current - $0 }
    }
}
