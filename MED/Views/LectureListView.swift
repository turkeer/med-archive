import SwiftUI
import SwiftData

/// Every session, newest first. Selection drives the detail column.
struct LectureListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context

    @Query(
        sort: [
            SortDescriptor(\Lecture.date, order: .reverse),
            SortDescriptor(\Lecture.startMinutes)
        ]
    )
    private var lectures: [Lecture]

    @State private var isAddingLecture = false

    /// Changed on every press of +, so the sheet always opens on a fresh form
    /// rather than reusing the previous one's state.
    @State private var newLectureSeed = UUID()

    var body: some View {
        List(selection: $selection) {
            ForEach(lectures) { lecture in
                LectureRow(lecture: lecture)
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
                    newLectureSeed = UUID()
                    isAddingLecture = true
                } label: {
                    Label("Yeni ders", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $isAddingLecture) {
            NewLectureSheet()
                .id(newLectureSeed)
        }
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

                    Text(lecture.displayTitle)
                        .font(.headline)
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
