import SwiftUI
import SwiftData

/// An academic and the lectures they gave.
struct InstructorDetailView: View {
    @Bindable var instructor: Instructor

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Akademisyen") {
                TextField("Ad", text: $instructor.name, prompt: Text("Ayşe Yılmaz"))
                    .formTextField()
                TextField("Unvan", text: $instructor.titleText, prompt: Text("Prof. Dr."))
                    .formTextField()
                TextField("Bölüm", text: $instructor.department, prompt: Text("Anatomi"))
                    .formTextField()
                TextField("E-posta", text: $instructor.email)
                    .formTextField()
            }

            LectureLinkList(lectures: instructor.lectures)
        }
        .formStyle(.grouped)
        .navigationTitle(instructor.name.isEmpty ? "(adsız akademisyen)" : instructor.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: "Bu akademisyen silinsin mi?",
                    explanation: "Oturumlar silinmez — yalnızca akademisyen alanları boşalır."
                ) {
                    context.delete(instructor)
                }
            }
        }
    }

    private var subtitle: String {
        [
            instructor.department.isEmpty ? nil : instructor.department,
            "\(instructor.lectures.count) oturum",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
