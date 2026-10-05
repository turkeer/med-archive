import SwiftData
import SwiftUI

/// A pending "add a lecture" press, carried as the sheet's item.
///
/// The day and period travel with the request rather than sitting in separate
/// state. With `sheet(isPresented:)` the content could be built from values
/// set a moment earlier, which is how adding to a past day ended up creating
/// the lecture on today.
struct NewLectureRequest: Identifiable {
    let id = UUID()
    var day: Date = Date()
    var slot: LessonSlot?
}

/// Creating a lecture.
struct NewLectureSheet: View {
    let initialDate: Date
    let initialSlot: LessonSlot?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The lecture is inserted as the sheet opens and deleted again on cancel.
    ///
    /// Working on a detached object looked tidier and was wrong: choosing a
    /// course, or letting the date fill in the committee, attaches the lecture
    /// to records that *are* in the store, and SwiftData saves it along with
    /// them. Cancelling then left an untitled ghost behind. Inserting up front
    /// makes the lifetime explicit instead.
    @State private var lecture: Lecture?

    init(initialDate: Date = Date(), initialSlot: LessonSlot? = nil) {
        self.initialDate = initialDate
        self.initialSlot = initialSlot
    }

    /// Either a course or a topic is enough. Demanding both would force empty
    /// fields for entries like "Anatomi — pratik" or a one-off seminar.
    private var canSave: Bool {
        guard let lecture else { return false }
        return lecture.course != nil || lecture.hasTopic
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Yeni oturum")
                .font(.headline)
                .padding(.top, 14)

            if let lecture {
                LectureEditor(lecture: lecture)
            } else {
                Spacer()
            }

            Divider()

            HStack {
                Spacer()

                Button("Vazgeç", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 540, height: 680)
        .onAppear(perform: create)
    }

    private func create() {
        guard lecture == nil else { return }

        let new = Lecture(
            date: initialDate,
            startMinutes: initialSlot?.start,
            endMinutes: initialSlot?.end
        )
        context.insert(new)

        // A brand new record has no committee to overwrite, so the date decides.
        new.committee = context.committee(covering: new.date)

        lecture = new
    }

    private func cancel() {
        if let lecture {
            context.delete(lecture)
        }
        dismiss()
    }

    private func save() {
        if let lecture {
            lecture.title = lecture.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        dismiss()
    }
}
