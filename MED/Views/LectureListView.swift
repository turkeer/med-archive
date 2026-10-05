import SwiftUI
import SwiftData

/// Every session, newest first. Selection drives the detail column.
struct LectureListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context

    @Query(
        sort: [
            SortDescriptor(\Lecture.date, order: .reverse),
            // Reverse chronological the whole way down: on a given day the
            // most recent lesson is the last period, so it belongs on top.
            SortDescriptor(\Lecture.startMinutes, order: .reverse)
        ]
    )
    private var lectures: [Lecture]

    @State private var newLectureRequest: NewLectureRequest?

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                LectureRow(lecture: row.lecture, part: row.part)
            }
            .onDelete(perform: deleteLectures)
        }
        .navigationTitle("Konular")
        .overlay {
            if lectures.isEmpty {
                ContentUnavailableView(
                    "Henüz oturum yok",
                    systemImage: "calendar.badge.plus",
                    description: Text("Sağ üstteki + ile ilk kaydını ekle.")
                )
            }
        }
        .toolbar {
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

    /// Rows are built in one pass. Looking the part numbers up per row would
    /// group the whole list again for every row.
    private var rows: [Row] {
        let numbers = LectureGrouping.partNumbers(for: lectures)
        return lectures.map { Row(lecture: $0, part: numbers[$0.persistentModelID]) }
    }

    private struct Row: Identifiable {
        let lecture: Lecture
        let part: (index: Int, total: Int)?

        var id: PersistentIdentifier { lecture.persistentModelID }
    }

    private func deleteLectures(at offsets: IndexSet) {
        for index in offsets {
            context.delete(lectures[index])
        }
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
