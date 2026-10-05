import SwiftUI
import SwiftData

/// Creating a lecture. The lecture object exists but is not inserted until
/// you save, so closing the sheet leaves nothing behind.
struct NewLectureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var lecture: Lecture

    /// The day the sheet opens on. The calendar passes the selected day so that
    /// adding from a day does not land on today.
    init(initialDate: Date = Date()) {
        _lecture = State(initialValue: Lecture(date: initialDate))
    }

    /// Either a course or a topic is enough. Demanding both would force empty
    /// fields for entries like "Anatomi — pratik" or a one-off seminar.
    private var canSave: Bool {
        lecture.course != nil || lecture.hasTopic
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Yeni ders")
                .font(.headline)
                .padding(.top, 14)

            LectureEditor(lecture: lecture)

            Divider()

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 540, height: 660)
    }

    private func save() {
        lecture.title = lecture.title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Hold the relationships, insert, then set them again. Assigning them
        // once more from an inserted object makes sure the graph is wired no
        // matter how the picks were made while the lecture was still detached.
        let course = lecture.course
        let instructor = lecture.instructor
        let committee = lecture.committee
        let tags = lecture.tags

        context.insert(lecture)

        lecture.course = course
        lecture.instructor = instructor
        lecture.committee = committee
        lecture.tags = tags

        dismiss()
    }
}
