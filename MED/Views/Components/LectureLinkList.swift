import SwiftUI
import SwiftData

/// The "its lectures" list that every related screen shows. Clicking a row
/// hands you off to that lecture on the Konular screen.
///
/// Emits its own `Section`s, so it goes straight into a `Form` rather than
/// inside one — nesting sections would be wrong when grouping is on.
struct LectureLinkList: View {
    let lectures: [Lecture]

    /// Heading used when the list is not grouped.
    var title = "Oturumlar"

    /// Committees hold lectures from several courses, so their list reads
    /// better grouped. The design calls for exactly that.
    var groupByCourse = false

    @Environment(AppNavigation.self) private var nav

    /// Swift demet elemanlarına key path yazmaya izin vermiyor, bu yüzden
    /// grupların kendi tipi var.
    private struct CourseGroup: Identifiable {
        let name: String
        let lectures: [Lecture]
        var id: String { name }
    }

    var body: some View {
        if lectures.isEmpty {
            Section(title) {
                Text("Bağlı oturum yok.")
                    .foregroundStyle(.secondary)
            }
        } else if groupByCourse {
            ForEach(groups) { group in
                Section {
                    ForEach(group.lectures) { lecture in
                        row(for: lecture, showCourse: false)
                    }
                } header: {
                    Text(group.name)
                }
            }
        } else {
            Section("\(title) (\(lectures.count))") {
                ForEach(byDate) { lecture in
                    row(for: lecture, showCourse: true)
                }
            }
        }
    }

    private var byDate: [Lecture] {
        lectures.sorted { $0.date > $1.date }
    }

    private var groups: [CourseGroup] {
        Dictionary(grouping: lectures) { $0.course?.name ?? "Dersi belirtilmemiş" }
            .map { CourseGroup(name: $0.key, lectures: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.name < $1.name }
    }

    private func row(for lecture: Lecture, showCourse: Bool) -> some View {
        Button {
            nav.show(lecture)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lecture.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    if showCourse, let course = lecture.course, lecture.hasTopic {
                        Text(course.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: course.colorHex))
                    }

                    Text(lecture.displayTitle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
