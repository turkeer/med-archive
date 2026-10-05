import SwiftUI
import SwiftData

/// The right-hand column. Edits are live — there is no separate save step.
struct LectureDetailView: View {
    let lecture: Lecture

    @Environment(\.modelContext) private var context
    @State private var isConfirmingDelete = false

    var body: some View {
        LectureEditor(lecture: lecture)
            // Resets the editor's own field state when a different lecture
            // is selected, instead of carrying half-typed text across.
            .id(lecture.persistentModelID)
            .navigationTitle(lecture.title.isEmpty ? "(başlıksız)" : lecture.title)
            .navigationSubtitle(lecture.timeRangeText)
            .toolbar {
                ToolbarItem {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Dersi sil", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "Bu ders silinsin mi?",
                isPresented: $isConfirmingDelete
            ) {
                Button("Sil", role: .destructive) {
                    context.delete(lecture)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Derse bağlı dosya kayıtları da silinir. Diskteki dosyalara dokunulmaz.")
            }
    }
}
