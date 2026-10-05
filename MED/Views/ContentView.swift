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
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch nav.section {
        case .calendar:
            CalendarMonthView(visibleMonth: $nav.visibleMonth, selectedDay: $nav.selectedDay)
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
            SelectionPlaceholder(text: "Soldaki kenar çubuğundan bir bölüm seç.")
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch nav.section {
        case .calendar:
            CalendarDayColumn(day: nav.selectedDay)
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
            SelectionPlaceholder(text: "Bir bölüm seç.")
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
            SelectionPlaceholder(text: "Ortadaki listeden bir oturum seç.")
        }
    }
}
