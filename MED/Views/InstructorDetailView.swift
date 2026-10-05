import SwiftUI
import SwiftData

/// An academic and the lectures they gave.
struct InstructorDetailView: View {
    @Bindable var instructor: Instructor

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section(L.instructor) {
                TextField(L.name, text: $instructor.name, prompt: Text("Ayşe Yılmaz"))
                    .formTextField()
                TextField(L.pick("Unvan", "Title"), text: $instructor.titleText, prompt: Text("Prof. Dr."))
                    .formTextField()
                TextField(L.pick("Bölüm", "Department"), text: $instructor.department, prompt: Text(L.pick("Anatomi", "Anatomy")))
                    .formTextField()
                TextField(L.pick("E-posta", "Email"), text: $instructor.email)
                    .formTextField()
            }

            LectureLinkList(lectures: instructor.lectures)
        }
        .formStyle(.grouped)
        .navigationTitle(instructor.name.isEmpty ? L.pick("(adsız akademisyen)", "(unnamed instructor)") : instructor.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: L.pick("Bu akademisyen silinsin mi?", "Delete this instructor?"),
                    explanation: L.pick(
                        "Oturumlar silinmez — yalnızca akademisyen alanları boşalır.",
                        "The sessions stay; only their instructor field is cleared."
                    )
                ) {
                    context.delete(instructor)
                }
            }
        }
    }

    private var subtitle: String {
        [
            instructor.department.isEmpty ? nil : instructor.department,
            L.sessionCount(instructor.lectures.count),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
