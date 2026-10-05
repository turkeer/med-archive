import Foundation
import Observation
import SwiftData

/// The sections of the permanent sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case calendar
    case lectures
    case courses
    case instructors
    case committees
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:        return L.pick("Özet", "Summary")
        case .calendar:    return L.calendar
        case .lectures:    return L.topics
        case .courses:     return L.courses
        case .instructors: return L.instructors
        case .committees:  return L.committees
        case .tags:        return L.tags
        }
    }

    var symbolName: String {
        switch self {
        case .home:        return "house"
        case .calendar:    return "calendar"
        case .lectures:    return "list.bullet.rectangle"
        case .courses:     return "books.vertical"
        case .instructors: return "person.2"
        case .committees:  return "square.stack.3d.up"
        case .tags:        return "tag"
        }
    }
}

/// How the calendar's right-hand column reads the selected week.
enum CalendarMode: String, CaseIterable, Identifiable {
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return L.pick("Hafta", "Week")
        case .day:  return L.pick("Gün", "Day")
        }
    }
}

/// What is selected, in one place, so that the related screens can hand you
/// off to a lecture: clicking a lecture under an instructor switches the
/// sidebar to Konular and selects it, rather than opening a dead end.
@Observable
final class AppNavigation {
    private static let sectionKey = "MEDLastSection"

    /// Remembered across launches. The summary is where a new install lands,
    /// but a habit is not something to argue with: if you work out of Konular,
    /// that is where the app opens.
    var section: SidebarSection? {
        didSet {
            guard let section else { return }
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey)
        }
    }

    /// Konular's filter and search box live here rather than in the view, so
    /// that the summary screen can hand the list a question to answer —
    /// "this committee's topics with no slides" — instead of only showing a
    /// number you then have to reproduce by hand.
    var lectureFilter = LectureFilter()
    var lectureQuery = ""

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.sectionKey) ?? ""
        section = SidebarSection(rawValue: stored) ?? .home
    }

    var calendarMode: CalendarMode = .week

    /// The month the calendar is showing, and the day picked inside it.
    var visibleMonth = Date()
    var selectedDay: Date? = Calendar.current.startOfDay(for: Date())

    var lectureID: PersistentIdentifier?
    var courseID: PersistentIdentifier?
    var instructorID: PersistentIdentifier?
    var committeeID: PersistentIdentifier?
    var tagID: PersistentIdentifier?

    func show(_ lecture: Lecture) {
        section = .lectures
        lectureID = lecture.persistentModelID
    }

    /// Opens Konular showing exactly what `filter` asks for, with no leftover
    /// search text narrowing it further.
    func showTopics(_ filter: LectureFilter) {
        lectureFilter = filter
        lectureQuery = ""
        section = .lectures
    }
}
