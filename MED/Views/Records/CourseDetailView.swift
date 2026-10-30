import SwiftUI
import SwiftData

/// A recurring course and everything taught under it.
struct CourseDetailView: View {
    @Bindable var course: Course

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section(L.course) {
                TextField(L.name, text: $course.name, prompt: Text(L.pick("Anatomi", "Anatomy")))
                    .formTextField()

                LabeledContent(L.color) {
                    ColorSwatchPicker(hex: $course.colorHex)
                }
            }

            LectureLinkList(lectures: course.lectures)
        }
        .formStyle(.grouped)
        .navigationTitle(course.name.isEmpty ? L.pick("(adsız ders)", "(unnamed course)") : course.name)
        .navigationSubtitle(L.sessionCount(course.lectures.count))
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: L.pick("Bu ders silinsin mi?", "Delete this course?"),
                    explanation: L.pick(
                        "Oturumlar silinmez — yalnızca ders alanları boşalır.",
                        "The sessions stay; only their course field is cleared."
                    )
                ) {
                    context.delete(course)
                }
            }
        }
    }
}
