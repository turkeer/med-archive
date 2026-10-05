import SwiftUI
import SwiftData

/// All lectures, newest first.
struct LectureListView: View {
    @Environment(\.modelContext) private var context

    @Query(
        sort: [
            SortDescriptor(\Lecture.date, order: .reverse),
            SortDescriptor(\Lecture.startMinutes)
        ]
    )
    private var lectures: [Lecture]

    @State private var isAddingLecture = false

    var body: some View {
        List {
            ForEach(lectures) { lecture in
                LectureRow(lecture: lecture)
            }
            .onDelete(perform: deleteLectures)
        }
        .navigationTitle("Dersler")
        .overlay {
            if lectures.isEmpty {
                ContentUnavailableView(
                    "Henüz ders yok",
                    systemImage: "calendar.badge.plus",
                    description: Text("Sağ üstteki + ile ilk dersini ekle.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingLecture = true
                } label: {
                    Label("Yeni ders", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $isAddingLecture) {
            LectureFormView()
        }
    }

    private func deleteLectures(at offsets: IndexSet) {
        for index in offsets {
            context.delete(lectures[index])
        }
    }
}

/// One line in the list. Deliberately plain for now.
private struct LectureRow: View {
    let lecture: Lecture

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(lecture.title.isEmpty ? "(başlıksız)" : lecture.title)
                    .font(.headline)

                Spacer()

                Text(lecture.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if !lecture.timeRangeText.isEmpty {
                    Label(lecture.timeRangeText, systemImage: "clock")
                }

                if let instructor = lecture.instructor {
                    Label(instructor.displayName, systemImage: "person")
                }

                if let committee = lecture.committee {
                    Label {
                        Text(committee.name)
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
