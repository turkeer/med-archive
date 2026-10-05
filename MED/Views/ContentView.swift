import SwiftUI
import SwiftData

/// Three columns: the permanent sidebar, the list for the chosen section, and
/// the selected record.
///
/// Each section keeps its own selection in `AppNavigation`, so switching away
/// from Akademisyenler and back lands you on the same person. A shared
/// navigation object is also what lets a lecture row under an instructor jump
/// to that lecture on the Konular screen.
struct ContentView: View {
    @State private var nav = AppNavigation()

    @Environment(\.modelContext) private var context

    /// The window's undo manager — the one the Edit menu's ⌘Z drives.
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $nav.section)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            detailColumn
        }
        .environment(nav)
        // Dates and months follow the chosen language, so a week heading does
        // not read "5 – 11 Eki" in an otherwise English window. Set here
        // rather than on the scene: reading the language inside a view's body
        // is what makes the window redraw when it changes.
        .environment(\.locale, L.locale)
        // Hands the store the window's undo manager rather than one of its
        // own. A private `UndoManager` would record every change faithfully
        // and ⌘Z would still do nothing, because the Edit menu does not know
        // about it: it drives whatever the responder chain hands it, which
        // for everything outside a text field is the window's.
        //
        // Set here rather than in `MEDApp`, because `modelContext` only
        // exists below `.modelContainer(_:)` — and this view is what that
        // modifier is applied to.
        .onAppear { context.undoManager = undoManager }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch nav.section {
        case .home:
            HomeDayColumn()
        case .calendar:
            CalendarMonthView(
                visibleMonth: $nav.visibleMonth,
                selectedDay: $nav.selectedDay,
                mode: $nav.calendarMode
            )
        case .lectures:
            LectureListView(selection: $nav.lectureID)
        case .courses:
            CourseListColumn(selection: $nav.courseID)
        case .instructors:
            InstructorListColumn(selection: $nav.instructorID)
        case .committees:
            CommitteeListColumn(selection: $nav.committeeID)
        case .tags:
            TagListColumn(selection: $nav.tagID)
        case nil:
            SelectionPlaceholder(text: L.pick("Soldaki kenar çubuğundan bir bölüm seç.", "Pick a section from the sidebar."))
        }
    }

    /// The week grid needs the wide column — five columns of lectures do not
    /// fit a list-width one — so the month grid stays on the left and this
    /// side switches between the week and a single day.
    @ViewBuilder
    private var calendarDetail: some View {
        switch nav.calendarMode {
        case .week:
            CalendarWeekView(
                selectedDay: $nav.selectedDay,
                visibleMonth: $nav.visibleMonth
            )
        case .day:
            CalendarDayColumn(day: nav.selectedDay)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch nav.section {
        case .home:
            HomeView()
        case .calendar:
            calendarDetail
        case .lectures:
            LectureDetailColumn(lectureID: nav.lectureID)
        case .courses:
            CourseDetailColumn(courseID: nav.courseID)
        case .instructors:
            InstructorDetailColumn(instructorID: nav.instructorID)
        case .committees:
            CommitteeDetailColumn(committeeID: nav.committeeID)
        case .tags:
            TagDetailColumn(tagID: nav.tagID)
        case nil:
            SelectionPlaceholder(text: L.pick("Bir bölüm seç.", "Pick a section."))
        }
    }
}

/// Resolves the selected id to a lecture, and survives that lecture being
/// deleted: the lookup simply stops finding it and the placeholder returns.
struct LectureDetailColumn: View {
    let lectureID: PersistentIdentifier?

    @Query private var lectures: [Lecture]

    var body: some View {
        if let lecture = lectures.first(where: { $0.persistentModelID == lectureID }) {
            LectureDetailView(lecture: lecture)
        } else {
            SelectionPlaceholder(text: L.pick("Ortadaki listeden bir oturum seç.", "Pick a session from the middle list."))
        }
    }
}
