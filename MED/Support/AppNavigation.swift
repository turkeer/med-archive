import Foundation
import Observation
import SwiftData

/// The sections of the permanent sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case calendar
    case lectures
    case search
    case courses
    case instructors
    case committees
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:    return L.calendar
        case .lectures:    return L.topics
        case .search:      return L.pick("Slaytlarda ara", "Search slides")
        case .courses:     return L.courses
        case .instructors: return L.instructors
        case .committees:  return L.committees
        case .tags:        return L.tags
        }
    }

    var symbolName: String {
        switch self {
        case .calendar:    return "calendar"
        case .lectures:    return "list.bullet.rectangle"
        case .search:      return "text.page.badge.magnifyingglass"
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
    var section: SidebarSection? = .lectures

    var calendarMode: CalendarMode = .week

    /// The month the calendar is showing, and the day picked inside it.
    var visibleMonth = Date()
    var selectedDay: Date? = Calendar.current.startOfDay(for: Date())

    /// The Ara screen's question and which page of which deck it is showing.
    ///
    /// Kept here like the other selections, so switching to Takvim and back
    /// does not throw away a search you are halfway through reading. Not
    /// written to disk: a question you asked once is not a setting.
    var slideQuery = ""
    var slidePage: SlidePageSelection?

    var lectureID: PersistentIdentifier?
    var courseID: PersistentIdentifier?
    var instructorID: PersistentIdentifier?
    var committeeID: PersistentIdentifier?
    var tagID: PersistentIdentifier?

    func show(_ lecture: Lecture) {
        section = .lectures
        lectureID = lecture.persistentModelID
    }
}

/// A page of a slide deck, as picked from the Ara screen.
///
/// Carries the query as well as the place, because the page is opened with
/// the matches marked on it — without the words there is nothing to mark.
struct SlidePageSelection: Hashable {
    let path: String
    let page: Int
    let query: String
}
