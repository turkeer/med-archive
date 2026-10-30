import SwiftUI
import SwiftData

/// The right-hand column: a lecture to read, and the editor when asked for.
///
/// It used to be the editor always. Clicking a lesson in the calendar landed
/// you in a form for changing it, which is not what clicking a lesson means —
/// so reading is the default now and editing is a button, the way Contacts
/// does it. Edits are still live once you are in it; there is no save step.
struct LectureDetailView: View {
    let lecture: Lecture

    @Environment(\.modelContext) private var context

    @State private var isEditing = false

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
        content
            .navigationTitle(lecture.displayTitle)
            .navigationSubtitle(subtitle)
            // Picking another lesson comes back to reading. Carrying edit
            // mode along would mean every lesson you looked at afterwards
            // opened as a form, which is the thing being fixed.
            .onChange(of: lecture.persistentModelID) { _, _ in
                isEditing = false
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        isEditing.toggle()
                    } label: {
                        if isEditing {
                            Label(L.pick("Bitti", "Done"), systemImage: "checkmark")
                        } else {
                            Label(L.pick("Düzenle", "Edit"), systemImage: "pencil")
                        }
                    }
                    .help(isEditing
                          ? L.pick("Düzenlemeyi bitir", "Finish editing")
                          : L.pick("Bu oturumu düzenle", "Edit this session"))
                }

                // Only while editing: in the way the rest of the time, and
                // one slip from deleting the lesson you were reading.
                if isEditing {
                    ToolbarItem {
                        DeleteRecordButton(
                            question: L.pick("Bu oturum silinsin mi?", "Delete this session?"),
                            explanation: L.pick(
                                "Bağlı dosya kayıtları da silinir. Diskteki dosyalara dokunulmaz.",
                                "Its file records go too. The files on disk are untouched."
                            )
                        ) {
                            context.delete(lecture)
                        }
                    }
                }
            }
    }

    /// The `id` resets the shown view's own state when a different lecture is
    /// selected, instead of carrying half-typed text across.
    ///
    /// It sits here rather than on `body`: applied up there it would take the
    /// `onChange` with it, so selecting another lesson would rebuild the
    /// watcher instead of firing it, and edit mode would never reset.
    @ViewBuilder
    private var content: some View {
        if isEditing {
            LectureEditor(lecture: lecture, showsFiles: true)
                .id(lecture.persistentModelID)
        } else {
            LectureReadView(lecture: lecture)
                .id(lecture.persistentModelID)
        }
    }
}
