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
    /// leading column, where the date would be noise.
    var dayMode = false

    @Environment(AppNavigation.self) private var nav

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
            Section("\(title) (\(groups.count))") {
                ForEach(groups) { group in
                    row(for: group, showCourse: true)
                }
            }
        }
    }

    private var groups: [LectureGroup] {
        // One day read as a timetable runs earliest first; a list with a date
        // axis runs the other way, consistently with that axis.
        LectureGrouping.groups(of: lectures, order: dayMode ? .timetable : .newestFirst)
    }

    private var courseRuns: [CourseRun] {
        Dictionary(grouping: groups) { $0.first.course?.name ?? "Dersi belirtilmemiş" }
            .map { CourseRun(name: $0.key, groups: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func leadingText(for group: LectureGroup) -> String {
        if dayMode {
            return LectureGrouping.slotLabel(for: group.lectures)
        }
        return group.first.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

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

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: group))
    }

    private func helpText(for group: LectureGroup) -> String {
        guard group.count > 1 else { return group.first.displayTitle }
        return "\(group.first.displayTitle) — \(group.count) ders, \(LectureGrouping.slotLabel(for: group.lectures))"
    }
}
