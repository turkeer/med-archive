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
        .overlay {
            // Full-screen reading sits above the whole split view rather than
            // in the detail column, so the sidebar and list get out of the way.
            // Still inside this window, so it shares `nav` and the lookup's
            // "open in atlas" hand-off keeps working.
            if let slide = nav.fullScreenSlide {
                SlideFullScreenReader(selection: slide)
                    .environment(nav)
                    .environment(\.locale, L.locale)
                    .transition(.opacity)
            }

            // The ⌘K palette sits above everything, including the full-screen
            // reader. Actions are built here because the JSON export needs the
            // model context, which only exists at this level.
            if nav.commandPaletteOpen {
                CommandPaletteView(
                    actions: CommandPalette.actions(
                        nav: nav,
                        context: context,
                        exportJSON: { ArchiveExport.save(from: context) }
                    )
                )
                .environment(nav)
                .environment(\.locale, L.locale)
                .transition(.opacity)
            }
        }
        // Publishes this window's navigation to the scene's ⌘K menu command.
        .focusedSceneValue(\.appNavigation, nav)
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
        case .workspace:
            WorkspaceView()
        case .calendar:
            CalendarMonthView(
                visibleMonth: $nav.visibleMonth,
                selectedDay: $nav.selectedDay,
                mode: $nav.calendarMode
            )
        case .lectures:
            LectureListView(selection: $nav.lectureID)
        case .search:
            SlideSearchView(query: $nav.slideQuery, selection: $nav.slidePage)
        case .glossary:
            GlossaryView(query: $nav.glossaryQuery, selection: $nav.glossaryPage)
        case .reference:
            ReferenceView(query: $nav.referenceQuery, selection: $nav.referencePage)
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
        case .workspace:
            SelectionPlaceholder(text: L.pick(
                "Çalışma alanı: bugünkü dersler ve aktif komitenin durumu solda. Bir satıra tıklamak seni o konuya götürür.",
                "Workspace: today's lessons and the active committee are on the left. Clicking a row takes you to that topic."
            ))
        case .calendar:
            calendarDetail
        case .lectures:
            LectureDetailColumn(lectureID: nav.lectureID)
        case .search:
            SlidePageDetail(selection: nav.slidePage)
        case .glossary:
            SlidePageDetail(selection: nav.glossaryPage)
        case .reference:
            SlidePageDetail(selection: nav.referencePage)
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

    @Environment(AppNavigation.self) private var nav
    @Query private var lectures: [Lecture]

    var body: some View {
        Group {
            if let reading = nav.readingSlide {
                SlideReaderColumn(selection: reading)
            } else if let lecture = lectures.first(where: { $0.persistentModelID == lectureID }) {
                LectureDetailView(lecture: lecture)
            } else {
                SelectionPlaceholder(text: L.pick("Ortadaki listeden bir oturum seç.", "Pick a session from the middle list."))
            }
        }
        // Picking another lesson leaves the reader; a slide you opened to read
        // belongs to the lesson you opened it from, not the next one.
        .onChange(of: lectureID) { _, _ in nav.readingSlide = nil }
    }
}

/// A slide read inside the app, with a way back to the lesson. The viewer
/// itself is the same one search and the atlas use, so selecting a term and
/// looking it up works here too — which is the whole point of reading in the
/// app rather than Quick Look.
struct SlideReaderColumn: View {
    let selection: SlidePageSelection

    @Environment(AppNavigation.self) private var nav

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    nav.readingSlide = nil
                } label: {
                    Label(L.pick("Derse dön", "Back to the lesson"), systemImage: "chevron.left")
                }
                .buttonStyle(.link)

                Spacer(minLength: 8)

                Label(
                    L.pick("Bir kelimeyi seç, sonra “Ara” ya da sağ tık", "Select a word, then “Look up” or right-click"),
                    systemImage: "character.cursor.ibeam"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

                Spacer(minLength: 8)

                Button {
                    nav.fullScreenSlide = selection
                } label: {
                    Label(L.pick("Tam ekran", "Full screen"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.link)
                .help(L.pick("Slaytı tüm pencereyi kaplayacak şekilde oku", "Read the slide filling the whole window"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            SlidePageDetail(selection: selection)
        }
    }
}

/// The same in-app viewer filling the whole window, for reading a slide without
/// the sidebar and list around it. Esc or the button leaves it; the term lookup
/// works here exactly as in the columned reader.
struct SlideFullScreenReader: View {
    let selection: SlidePageSelection

    @Environment(AppNavigation.self) private var nav

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    nav.fullScreenSlide = nil
                } label: {
                    Label(L.pick("Küçült", "Exit full screen"), systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.link)
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 8)

                Label(
                    L.pick("Bir kelimeyi seç, sonra “Ara” ya da sağ tık", "Select a word, then “Look up” or right-click"),
                    systemImage: "character.cursor.ibeam"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            SlidePageDetail(selection: selection)
        }
        .background(.background)
    }
}
