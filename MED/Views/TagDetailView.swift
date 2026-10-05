import SwiftUI
import SwiftData

/// A tag, what carries it, and a way to fold it into another one.
struct TagDetailView: View {
    @Bindable var tag: Tag

    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var nav

    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var mergeTargetID: PersistentIdentifier?

    private var mergeCandidates: [Tag] {
        allTags.filter { $0.persistentModelID != tag.persistentModelID }
    }

    private var mergeTarget: Tag? {
        mergeCandidates.first { $0.persistentModelID == mergeTargetID }
    }

    var body: some View {
        Form {
            Section(L.tag) {
                TextField(L.name, text: $tag.name, prompt: Text(L.pick("membran", "membrane")))
                    .formTextField()

                LabeledContent(L.color) {
                    ColorSwatchPicker(hex: $tag.colorHex)
                }
            }

            LectureLinkList(lectures: tag.lectures)

            if !mergeCandidates.isEmpty {
                Section {
                    Picker(L.pick("Şununla birleştir", "Merge into"), selection: $mergeTargetID) {
                        Text(L.pick("Seç", "Choose")).tag(PersistentIdentifier?.none)
                        ForEach(mergeCandidates) { candidate in
                            Text(candidate.name.isEmpty ? L.unnamed : candidate.name)
                                .tag(PersistentIdentifier?.some(candidate.persistentModelID))
                        }
                    }

                    Button(L.pick("Birleştir", "Merge"), action: merge)
                        .disabled(mergeTarget == nil)
                } header: {
                    Text(L.pick("Birleştir", "Merge"))
                } footer: {
                    Text(L.pick(
                        "Bu etiketin bütün oturumları seçilen etikete taşınır, sonra bu etiket silinir.",
                        "Every session on this tag moves to the chosen one, then this tag is deleted."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tag.name.isEmpty ? L.pick("(adsız etiket)", "(unnamed tag)") : tag.name)
        .navigationSubtitle(L.sessionCount(tag.lectures.count))
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: L.pick("Bu etiket silinsin mi?", "Delete this tag?"),
                    explanation: L.pick(
                        "Oturumlar silinmez — yalnızca bu etiket onlardan kalkar.",
                        "The sessions stay; only this tag comes off them."
                    )
                ) {
                    context.delete(tag)
                }
            }
        }
    }

    private func merge() {
        guard let target = mergeTarget else { return }

        // Snapshot first: appending to a lecture's tags touches the same
        // relationship we would otherwise be iterating.
        for lecture in Array(tag.lectures) {
            let alreadyThere = lecture.tags.contains { $0.persistentModelID == target.persistentModelID }
            if !alreadyThere {
                lecture.tags.append(target)
            }
        }

        context.delete(tag)
        nav.tagID = target.persistentModelID
    }
}
