import SwiftData
import SwiftUI

/// The "its lectures" list that every related screen shows. Clicking a row
/// hands you off to that lecture on the Konular screen.
///
/// Rows are **topics, not records.** One subject taught across two periods
/// with a break in between is two records, and showing it as two cards reads
/// as two lessons when it is one — so parts of a topic fold into a single row
/// that says how many periods it took. The complete record list lives on the
/// Konular screen, where every part is selectable in its own right.
///
/// Emits its own `Section`s, so it goes straight into a `Form` rather than
/// inside one — nesting sections would be wrong when grouping is on.
struct LectureLinkList: View {
    let lectures: [Lecture]

    /// Heading used when the list is not grouped by course.
    var title = "Oturumlar"

    /// Committees hold lectures from several courses, so their list reads
    /// better grouped. The design calls for exactly that.
    var groupByCourse = false

    /// Everything in the list falls on one day: show the periods in the
    /// leading column, where the date would be noise, and order by period
    /// regardless of what else is chosen.
    var dayMode = false

    @Environment(AppNavigation.self) private var nav

    /// Remembered across screens and launches — a sort order you chose once
    /// is not something to choose again on every course.
    @AppStorage("lectureListSort") private var sort: LectureSort = .newestFirst

    @State private var query = ""

    /// Searching and sorting a handful of rows is noise, not help.
    private var showsControls: Bool {
        !dayMode && lectures.count > 5
    }

    /// Swift does not allow key paths into tuples, so the course runs get
    /// their own type.
    private struct CourseRun: Identifiable {
        let name: String
        let groups: [LectureGroup]
        var id: String { name }
    }

    var body: some View {
        if lectures.isEmpty {
            Section(title) {
                Text("Bağlı oturum yok.")
                    .foregroundStyle(.secondary)
            }
        } else {
            controls

            if visibleGroups.isEmpty {
                Section {
                    Text("“\(query)” ile eşleşen oturum yok.")
                        .foregroundStyle(.secondary)
                }
            } else if groupByCourse {
                ForEach(courseRuns) { run in
                    Section {
                        ForEach(run.groups) { group in
                            row(for: group, showCourse: false)
                        }
                    } header: {
                        Text(run.name)
                    }
                }
            } else {
                Section(heading) {
                    ForEach(visibleGroups) { group in
                        row(for: group, showCourse: true)
                    }
                }
            }
        }
    }

    private var heading: String {
        let count = visibleGroups.count
        return query.isEmpty ? "\(title) (\(count))" : "\(title) — \(count) sonuç"
    }

    // MARK: Search and sort

    @ViewBuilder
    private var controls: some View {
        if showsControls {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    // Just "Ara": a placeholder listing every searched field
                    // wrapped onto three lines and made the row tall and ugly.
                    // The detail belongs in the tooltip.
                    TextField("Ara", text: $query, prompt: Text("Ara"))
                        .textFieldStyle(.plain)
                        .borderlessFormTextField()
                        .lineLimit(1)
                        .help("Konu, ders, akademisyen, komite, etiket, not ve dosya adında arar")

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Aramayı temizle")
                    }

                    Divider()
                        .frame(height: 16)

                    sortMenu
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LectureSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if option == sort {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sort.title)
                    .font(.caption)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sıralama")
    }

    // MARK: Data

    private var visibleGroups: [LectureGroup] {
        let all = LectureGrouping.groups(of: lectures, sort: dayMode ? .oldestFirst : sort)

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }

        return all.filter { group in
            group.lectures.contains { LectureSearch.matches($0, query: needle) }
        }
    }

    private var courseRuns: [CourseRun] {
        Dictionary(grouping: visibleGroups) { $0.first.course?.name ?? "Dersi belirtilmemiş" }
            .map { CourseRun(name: $0.key, groups: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func leadingText(for group: LectureGroup) -> String {
        if dayMode {
            return LectureGrouping.slotLabel(for: group.lectures)
        }
        return group.first.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: Rows

    private func row(for group: LectureGroup, showCourse: Bool) -> some View {
        Button {
            nav.show(group.first)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(leadingText(for: group))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    if showCourse, let course = group.first.course, group.first.hasTopic {
                        Text(course.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: course.colorHex))
                    }

                    HStack(spacing: 5) {
                        Text(group.first.displayTitle)

                        FormatBadge(format: group.first.format)

                        if group.count > 1 {
                            Text("\(group.count) ders")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.16), in: Capsule())
                        }
                    }
                }

                Spacer()

                // Says at a glance which topics still have no slides.
                if hasFiles(group) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: group))
    }

    private func hasFiles(_ group: LectureGroup) -> Bool {
        group.lectures.contains { !$0.files.isEmpty }
    }

    private func helpText(for group: LectureGroup) -> String {
        var parts = [group.first.displayTitle]

        if group.count > 1 {
            parts.append("\(group.count) ders, \(LectureGrouping.slotLabel(for: group.lectures))")
        }

        let fileCount = group.lectures.reduce(0) { $0 + $1.files.count }
        if fileCount > 0 {
            parts.append("\(fileCount) dosya")
        }

        return parts.joined(separator: " — ")
    }
}
