import SwiftUI
import SwiftData

/// The right-hand column. Edits are live — there is no separate save step.
struct LectureDetailView: View {
    let lecture: Lecture

    @Environment(\.modelContext) private var context

    /// Course and time, whichever of them is set. The course is left out when
    /// the title is already standing in for it.
    private var subtitle: String {
        [
            lecture.hasTopic ? lecture.course?.name : nil,
            lecture.scheduleText.isEmpty ? nil : lecture.scheduleText,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        LectureEditor(lecture: lecture)
            // Resets the editor's own field state when a different lecture
            // is selected, instead of carrying half-typed text across.
            .id(lecture.persistentModelID)
            .navigationTitle(lecture.displayTitle)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem {
                    DeleteRecordButton(
                        question: "Bu oturum silinsin mi?",
                        explanation: "Bağlı dosya kayıtları da silinir. Diskteki dosyalara dokunulmaz."
                    ) {
                        context.delete(lecture)
                    }
                }
            }
    }
}
