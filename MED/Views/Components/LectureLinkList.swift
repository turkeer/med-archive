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
    var title = L.sessions

    /// Committees hold lectures from several courses, so their list reads
    /// better grouped. The design calls for exactly that.
    var groupByCourse = false

    /// Everything in the list falls on one day: show the periods in the
    /// leading column, where the date would be noise, and order by period
    /// regardless of what else is chosen.
    var dayMode = false

    @Environment(AppNavigation.self) private var nav
    @Environment(SlideIndex.self) private var slideIndex

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
                Text(L.pick("Bağlı oturum yok.", "No sessions linked."))
                    .foregroundStyle(.secondary)
            }
        } else {
            controls

            if visibleGroups.isEmpty {
                Section {
                    Text(L.pick("“\(query)” ile eşleşen oturum yok.", "No session matches “\(query)”."))
                        .foregroundStyle(.secondary)
                }
            } else if groupByCourse {
                ForEach(courseRuns) { run in
                    Section {
                        ForEach(run.groups) { group in
                            row(for: group, showCourse: false)
                        }
                    } header: {
                        courseHeader(run)
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
        if query.isEmpty { return "\(title) (\(count))" }
        return "\(title) — " + L.pick("\(count) sonuç", "\(count) results")
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
                    TextField(L.search, text: $query, prompt: Text(L.search))
                        .textFieldStyle(.plain)
                        .borderlessFormTextField()
                        .lineLimit(1)
                        .help(L.pick(
                            "Konu, ders, akademisyen, komite, etiket, not, dosya adı ve slaytların içinde arar",
                            "Searches topic, course, instructor, committee, tag, notes, file names and inside the slides"
                        ))

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L.pick("Aramayı temizle", "Clear search"))
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
        .help(L.sort)
    }

    // MARK: Data

    private var visibleGroups: [LectureGroup] {
        let all = LectureGrouping.groups(of: lectures, sort: dayMode ? .oldestFirst : sort)

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }

        let slideHits = slideIndex.matchingPaths(query: needle)

        return all.filter { group in
            group.lectures.contains { LectureSearch.matches($0, query: needle, slideHits: slideHits) }
        }
    }

    private var courseRuns: [CourseRun] {
        Dictionary(grouping: visibleGroups, by: courseName)
            .map { CourseRun(name: $0.key, groups: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func courseName(of group: LectureGroup) -> String {
        group.first.course?.name ?? L.pick("Dersi belirtilmemiş", "No course set")
    }

    /// What a course heading reports: of the topics whose day has come, how
    /// many have a file on them, and how many are still ahead.
    private struct Coverage {
        var covered = 0
        var due = 0
        var upcoming = 0
    }

    /// How many of each course's topics have a file on them.
    ///
    /// Counted in topics, like the rows themselves: one subject taught over
    /// two periods is one thing to find slides for, not two.
    ///
    /// **Only topics whose day has arrived are counted.** A lesson next week
    /// is not a lesson whose slides are missing, and counting it as one made
    /// the number read as a warning when nothing was wrong: a committee two
    /// days in showed 20/74 — a fifth covered — when 51 of those 74 had not
    /// been taught yet and the real figure was 20/23. A gauge that cries wolf
    /// at the start of every committee is a gauge you stop reading.
    ///
    /// Counted over the course's own topics rather than the ones a search has
    /// left behind. A number that moved while you typed would be describing
    /// the search instead of the course, and the question being asked here —
    /// how much of this course is still missing — is about the course.
    private var coverageByCourse: [String: Coverage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var result: [String: Coverage] = [:]

        for group in LectureGrouping.groups(of: lectures) {
            let name = courseName(of: group)
            var entry = result[name] ?? Coverage()

            // Today counts as due: slides for the morning's lesson are
            // something you can already be missing by the afternoon.
            if calendar.startOfDay(for: group.first.date) > today {
                entry.upcoming += 1
            } else {
                entry.due += 1
                if hasFiles(group) { entry.covered += 1 }
            }

            result[name] = entry
        }

        return result
    }

    /// A course heading with how much of it has slides beside it. This is the
    /// number you want before an exam: which course still needs chasing up.
    private func courseHeader(_ run: CourseRun) -> some View {
        let coverage = coverageByCourse[run.name] ?? Coverage()

        return HStack(spacing: 8) {
            Text(run.name)

            Spacer(minLength: 8)

            // Nothing taught yet means nothing to be missing, so no gauge.
            if coverage.due > 0 {
                CoverageGauge(
                    covered: coverage.covered,
                    due: coverage.due,
                    upcoming: coverage.upcoming
                )
            }
        }
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: 104, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    meta(for: group, showCourse: showCourse)

                    Text(group.first.displayTitle)
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

    /// The caption line above a row's topic: the course it belongs to, whether
    /// it is a lab or an exam, and how many lessons the topic took.
    ///
    /// The count used to sit next to the topic, which was the wrong place: it
    /// ate into the width the topic had to wrap in, so a long name took an
    /// extra line to say the same thing. Up here it costs nothing — the course
    /// name is two words and the line is otherwise empty.
    @ViewBuilder
    private func meta(for group: LectureGroup, showCourse: Bool) -> some View {
        if showsCourseName(group, showCourse: showCourse)
            || group.first.format != .theoretical
            || group.count > 1 {
            HStack(spacing: 5) {
                if showsCourseName(group, showCourse: showCourse), let course = group.first.course {
                    Text(course.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: course.colorHex))
                }

                FormatBadge(format: group.first.format)

                if group.count > 1 {
                    Text(L.lessonCount(group.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.16), in: Capsule())
                }
            }
        }
    }

    /// Hidden when the list is already grouped by course, and when the row has
    /// no topic of its own — `displayTitle` is then showing the course name.
    private func showsCourseName(_ group: LectureGroup, showCourse: Bool) -> Bool {
        showCourse && group.first.course != nil && group.first.hasTopic
    }

    private func hasFiles(_ group: LectureGroup) -> Bool {
        group.lectures.contains { !$0.files.isEmpty }
    }

    private func helpText(for group: LectureGroup) -> String {
        var parts = [group.first.displayTitle]

        if group.count > 1 {
            parts.append(L.lessonCount(group.count) + ", \(LectureGrouping.slotLabel(for: group.lectures))")
        }

        let fileCount = group.lectures.reduce(0) { $0 + $1.files.count }
        if fileCount > 0 {
            parts.append(L.fileCount(fileCount))
        }

        return parts.joined(separator: " — ")
    }
}

/// "10/25" and a bar: how many of a course's taught topics have a file
/// attached. Lessons still ahead are not part of the fraction; they are
/// mentioned in the tooltip so the scale is still visible.
///
/// Green only when there is nothing left to find, because that is the one
/// state worth spotting from across the row.
private struct CoverageGauge: View {
    let covered: Int
    let due: Int
    let upcoming: Int

    private var fraction: Double {
        due == 0 ? 0 : Double(covered) / Double(due)
    }

    private let width: CGFloat = 46

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: width, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(covered == due ? Color.green : Color.accentColor)
                        .frame(width: width * fraction, height: 4)
                }

            Text("\(covered)/\(due)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help(helpText)
    }

    /// Phrased without a suffix on the numbers: the Turkish ending follows the
    /// number's last vowel (0'ında, 3'ünde, 7'sinde), so no single ending is
    /// right for all of them.
    private var helpText: String {
        let taught = L.pick(
            "slayt: işlenen \(due) konudan \(covered) tanesinde",
            "slides: \(covered) of \(due) topics taught"
        )

        guard upcoming > 0 else { return taught }

        return taught + L.pick(
            " · \(upcoming) konu ileride",
            " · \(upcoming) still to come"
        )
    }
}
