import SwiftUI
import SwiftData

/// Every session in the archive. Selection drives the detail column.
///
/// Rows here are **records, not topics**: the related screens fold the parts
/// of one topic into a single row, but this is the complete list, where each
/// lesson is selectable in its own right.
///
/// This is also the only screen that sees everything, so searching and
/// filtering live here rather than in a section of their own. A second place
/// to search sessions would be a second place that can disagree with this one
/// about what a hit is, for no gain: the sidebar's own sections already answer
/// "which courses do I have", and they hold a handful of records each.
struct LectureListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context

    /// Unsorted on purpose. Two of the four orders sort by `displayTitle`,
    /// which is computed, so no `SortDescriptor` can express them — ordering
    /// is `LectureSort.precedes` for all four, in one place.
    @Query private var lectures: [Lecture]

    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Instructor.name) private var instructors: [Instructor]
    @Query(sort: \Committee.startDate, order: .reverse) private var committees: [Committee]

    /// Shared with the related screens' lists and remembered across launches:
    /// an order you chose once is not something to choose again per screen.
    @AppStorage("lectureListSort") private var sort: LectureSort = .newestFirst

    @State private var query = ""
    @State private var filter = LectureFilter()
    @State private var newLectureRequest: NewLectureRequest?

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                LectureRow(lecture: row.lecture, part: row.part)
            }
            .onDelete(perform: deleteLectures)
        }
        .navigationTitle("Konular")
        .searchable(text: $query, prompt: "Ara")
        .safeAreaInset(edge: .top, spacing: 0) {
            activeFilterBar
        }
        .overlay {
            emptyState
        }
        .toolbar {
            ToolbarItem {
                filterMenu
            }

            ToolbarItem {
                sortMenu
            }

            ToolbarItem {
                Button {
                    newLectureRequest = NewLectureRequest()
                } label: {
                    Label("Yeni ders", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $newLectureRequest) { request in
            NewLectureSheet(initialDate: request.day, initialSlot: request.slot)
        }
    }

    // MARK: Rows

    /// Rows are built in one pass. Looking the part numbers up per row would
    /// group the whole list again for every row.
    ///
    /// Part numbers and the file gaps are read from the **whole** archive, not
    /// from what is visible: part 1 of 2 stays "(1/2)" while a filter hides
    /// its sibling, and a topic does not become "missing its slides" because
    /// the part holding them was filtered out.
    private var rows: [Row] {
        let numbers = LectureGrouping.partNumbers(for: lectures)
        let lacking = filter.missingFilesOnly
            ? LectureGrouping.lacksFiles(among: lectures)
            : Set<PersistentIdentifier>()

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return lectures
            .filter { filter.matches($0, lackingFiles: lacking) }
            .filter { needle.isEmpty || LectureSearch.matches($0, query: needle) }
            .sorted { sort.precedes($0, $1) }
            .map { Row(lecture: $0, part: numbers[$0.persistentModelID]) }
    }

    private struct Row: Identifiable {
        let lecture: Lecture
        let part: (index: Int, total: Int)?

        var id: PersistentIdentifier { lecture.persistentModelID }
    }

    /// Deletes what the row actually points at. Indexing into the unfiltered
    /// query here would delete a different session than the one swiped away
    /// the moment a filter, a search or any order but the default is on.
    private func deleteLectures(at offsets: IndexSet) {
        let visible = rows
        for index in offsets {
            context.delete(visible[index].lecture)
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        if lectures.isEmpty {
            ContentUnavailableView(
                "Henüz oturum yok",
                systemImage: "calendar.badge.plus",
                description: Text("Sağ üstteki + ile ilk kaydını ekle.")
            )
        } else if rows.isEmpty {
            // Says which of the two narrowed it down to nothing, because the
            // fix differs: clear the box, or clear the filter.
            ContentUnavailableView {
                Label("Eşleşen oturum yok", systemImage: "magnifyingglass")
            } description: {
                Text(emptyReason)
            } actions: {
                if filter.isActive {
                    Button("Filtreleri temizle") {
                        filter = LectureFilter()
                    }
                }
            }
        }
    }

    private var emptyReason: String {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasQuery, filter.isActive {
            return "“\(query)” aramasına ve açık filtrelere uyan oturum yok."
        }
        if hasQuery {
            return "“\(query)” ile eşleşen oturum yok."
        }
        return "Açık filtrelere uyan oturum yok."
    }

    // MARK: Sorting

    private var sortMenu: some View {
        Menu {
            ForEach(LectureSort.allCases) { option in
                pickButton(option.title, isOn: option == sort) {
                    sort = option
                }
            }
        } label: {
            Label("Sıralama", systemImage: "arrow.up.arrow.down")
        }
        .help("Sıralama: \(sort.title)")
    }

    // MARK: Filtering

    private var filterMenu: some View {
        Menu {
            Section("Ders") {
                pickButton("Hepsi", isOn: filter.courseID == nil) {
                    filter.courseID = nil
                }
                ForEach(courses) { course in
                    pickButton(course.name, isOn: filter.courseID == course.persistentModelID) {
                        filter.courseID = course.persistentModelID
                    }
                }
            }

            Section("Akademisyen") {
                pickButton("Hepsi", isOn: filter.instructorID == nil) {
                    filter.instructorID = nil
                }
                ForEach(instructors) { instructor in
                    pickButton(
                        instructor.displayName,
                        isOn: filter.instructorID == instructor.persistentModelID
                    ) {
                        filter.instructorID = instructor.persistentModelID
                    }
                }
            }

            Section("Komite") {
                pickButton("Hepsi", isOn: filter.committeeID == nil) {
                    filter.committeeID = nil
                }
                ForEach(committees) { committee in
                    pickButton(
                        committee.shortLabel,
                        isOn: filter.committeeID == committee.persistentModelID
                    ) {
                        filter.committeeID = committee.persistentModelID
                    }
                }
            }

            Section("Tür") {
                pickButton("Hepsi", isOn: filter.format == nil) {
                    filter.format = nil
                }
                ForEach(LectureFormat.allCases) { format in
                    pickButton(format.title, isOn: filter.format == format) {
                        filter.format = format
                    }
                }
            }

            Section {
                pickButton("Dosyası olmayanlar", isOn: filter.missingFilesOnly) {
                    filter.missingFilesOnly.toggle()
                }
            }

            if filter.isActive {
                Divider()
                Button("Filtreleri temizle") {
                    filter = LectureFilter()
                }
            }
        } label: {
            Label(
                "Filtre",
                systemImage: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help(filter.isActive ? "Filtre açık" : "Filtrele")
    }

    /// A menu row that shows a tick when it is the current choice — the same
    /// shape the sort menu has always had.
    private func pickButton(
        _ title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// What is filtered, spelled out above the list.
    ///
    /// A filled toolbar icon says *that* something is filtered; it cannot say
    /// what, and a list quietly missing half the archive is the one thing a
    /// filter must never do silently. Each chip removes its own condition, so
    /// undoing one does not mean reopening the menu and hunting for it.
    @ViewBuilder
    private var activeFilterBar: some View {
        if filter.isActive {
            VStack(spacing: 0) {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    if let course = selectedCourse {
                        Chip(text: course.name, color: Color(hex: course.colorHex)) {
                            filter.courseID = nil
                        }
                    }

                    if let instructor = selectedInstructor {
                        Chip(text: instructor.displayName) {
                            filter.instructorID = nil
                        }
                    }

                    if let committee = selectedCommittee {
                        Chip(text: committee.shortLabel, color: Color(hex: committee.colorHex)) {
                            filter.committeeID = nil
                        }
                    }

                    if let format = filter.format {
                        Chip(text: format.title) {
                            filter.format = nil
                        }
                    }

                    if filter.missingFilesOnly {
                        Chip(text: "Dosyası olmayanlar") {
                            filter.missingFilesOnly = false
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.bar)
        }
    }

    private var selectedCourse: Course? {
        courses.first { $0.persistentModelID == filter.courseID }
    }

    private var selectedInstructor: Instructor? {
        instructors.first { $0.persistentModelID == filter.instructorID }
    }

    private var selectedCommittee: Committee? {
        committees.first { $0.persistentModelID == filter.committeeID }
    }
}

/// One line in the list.
private struct LectureRow: View {
    let lecture: Lecture

    /// Which of several parts of one topic this is.
    let part: (index: Int, total: Int)?

    private var titleText: String {
        guard let part, lecture.hasTopic else { return lecture.displayTitle }
        return "\(lecture.displayTitle) (\(part.index)/\(part.total))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    // Only when there is a topic of its own — otherwise
                    // displayTitle is already showing the course name.
                    if let course = lecture.course, lecture.hasTopic {
                        Text(course.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: course.colorHex))
                    }

                    HStack(spacing: 5) {
                        Text(titleText)
                            .font(.headline)

                        FormatBadge(format: lecture.format)
                    }
                }

                Spacer()

                Text(lecture.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !lecture.scheduleText.isEmpty {
                    Label(lecture.scheduleText, systemImage: "clock")
                }

                if let instructor = lecture.instructor {
                    Label(instructor.displayName, systemImage: "person")
                }

                if !lecture.files.isEmpty {
                    Label("\(lecture.files.count)", systemImage: "paperclip")
                }

                if let committee = lecture.committee {
                    Label {
                        Text(committee.shortLabel)
                    } icon: {
                        Circle()
                            .fill(Color(hex: committee.colorHex))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            if !lecture.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(lecture.tags.sorted { $0.name < $1.name }) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: tag.colorHex).opacity(0.25), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
