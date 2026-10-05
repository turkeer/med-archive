import Foundation
import Observation
import SwiftData

/// The sections of the permanent sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case calendar
    case lectures
    case courses
    case instructors
    case committees
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:    return "Takvim"
        case .lectures:    return "Konular"
        case .courses:     return "Dersler"
        case .instructors: return "Akademisyenler"
        case .committees:  return "Komiteler"
        case .tags:        return "Etiketler"
        }
    }

    var symbolName: String {
        switch self {
        case .calendar:    return "calendar"
        case .lectures:    return "list.bullet.rectangle"
        case .courses:     return "books.vertical"
        case .instructors: return "person.2"
        case .committees:  return "square.stack.3d.up"
        case .tags:        return "tag"
        }
    }
}

/// What is selected, in one place, so that the related screens can hand you
/// off to a lecture: clicking a lecture under an instructor switches the
/// sidebar to Konular and selects it, rather than opening a dead end.
@Observable
final class AppNavigation {
    var section: SidebarSection? = .lectures

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
}
