import SwiftUI
import SwiftData

/// A recurring course and everything taught under it.
struct CourseDetailView: View {
    @Bindable var course: Course

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Ders") {
                TextField("Ad", text: $course.name, prompt: Text("Anatomi"))

                LabeledContent("Renk") {
                    ColorSwatchPicker(hex: $course.colorHex)
                }
            }

            LectureLinkList(lectures: course.lectures)
        }
        .formStyle(.grouped)
        .navigationTitle(course.name.isEmpty ? "(adsız ders)" : course.name)
        .navigationSubtitle("\(course.lectures.count) oturum")
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: "Bu ders silinsin mi?",
                    explanation: "Oturumlar silinmez — yalnızca ders alanları boşalır."
                ) {
                    context.delete(course)
                }
            }
        }
    }
}
