import Foundation
import Observation
import SwiftData

/// The sections of the permanent sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case workspace
    case calendar
    case lectures
    case search
    case glossary
    case reference
    case courses
    case instructors
    case committees
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace:   return L.workspace
        case .calendar:    return L.calendar
        case .lectures:    return L.topics
        case .search:      return L.pick("Slaytlarda ara", "Search slides")
        case .glossary:    return L.glossary
        case .reference:   return L.pick("Atlas", "Atlas")
        case .courses:     return L.courses
        case .instructors: return L.instructors
        case .committees:  return L.committees
        case .tags:        return L.tags
        }
    }

    var symbolName: String {
        switch self {
        case .workspace:   return "square.grid.2x2"
        case .calendar:    return "calendar"
        case .lectures:    return "list.bullet.rectangle"
        case .search:      return "text.page.badge.magnifyingglass"
        case .glossary:    return "character.book.closed"
        case .reference:   return "book.pages"
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

/// The four ways the Atlas screen can be read. Held in navigation rather than
/// the view so a "look this up in the atlas" action from another screen can
/// drop you straight into search.
enum ReferenceSectionMode: String, CaseIterable, Identifiable {
    case contents, glossary, figures, search
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contents: return L.pick("İçindekiler", "Contents")
        case .glossary: return L.pick("Sözlük", "Glossary")
        case .figures:  return L.pick("Figürler", "Figures")
        case .search:   return L.pick("Ara", "Search")
        }
    }
}

/// What is selected, in one place, so that the related screens can hand you
/// off to a lecture: clicking a lecture under an instructor switches the
/// sidebar to Konular and selects it, rather than opening a dead end.
@Observable
final class AppNavigation {
    var section: SidebarSection? = .workspace

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

    /// The Sözlük screen's search and which slide a chosen definition points
    /// at. Kept apart from the Ara screen's own `slidePage` so the two screens
    /// do not clobber each other's selection when you switch between them.
    var glossaryQuery = ""
    var glossaryPage: SlidePageSelection?

    /// The Atlas screen's search and the page of the reference book it is
    /// showing. Its own selection, kept apart from the other screens so
    /// switching sections does not clobber it.
    var referenceQuery = ""
    var referencePage: SlidePageSelection?
    var referenceMode: ReferenceSectionMode = .contents

    /// A slide opened for reading inside the app's own PDF viewer — where you
    /// can select a term and look it up — rather than in Quick Look. Lives here
    /// so the lecture detail column can swap to the reader and back. Cleared
    /// when another lecture is picked.
    var readingSlide: SlidePageSelection?

    /// A slide shown filling the whole window for distraction-free study, still
    /// in the app's own viewer so term lookup keeps working — the difference
    /// from Quick Look. Independent of `readingSlide`: you can go full screen
    /// straight from the lesson, or expand the inline reader.
    var fullScreenSlide: SlidePageSelection?

    /// Open `path` in the in-app reader, from its first page.
    func readSlide(path: String) {
        readingSlide = SlidePageSelection(path: path, page: 1, query: "")
    }

    /// Show `path` full-screen in the in-app viewer, from its first page.
    func readSlideFullScreen(path: String) {
        fullScreenSlide = SlidePageSelection(path: path, page: 1, query: "")
    }

    var lectureID: PersistentIdentifier?
    var courseID: PersistentIdentifier?
    var instructorID: PersistentIdentifier?
    var committeeID: PersistentIdentifier?
    var tagID: PersistentIdentifier?

    func show(_ lecture: Lecture) {
        section = .lectures
        lectureID = lecture.persistentModelID
    }

    /// Jump to the Atlas and search it for `term` — the crossover from a slide
    /// hit or a glossary entry to the reference book. Lands in full-text search
    /// because that finds the term anywhere in the book, figures included.
    func openInAtlas(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        referenceQuery = trimmed
        referenceMode = .search
        referencePage = nil
        section = .reference
        // Leave any slide reader so the atlas is actually what you see.
        readingSlide = nil
        fullScreenSlide = nil
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
