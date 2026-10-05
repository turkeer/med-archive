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
            Section("Etiket") {
                TextField("Ad", text: $tag.name, prompt: Text("membran"))

                LabeledContent("Renk") {
                    ColorSwatchPicker(hex: $tag.colorHex)
                }
            }

            LectureLinkList(lectures: tag.lectures)

            if !mergeCandidates.isEmpty {
                Section {
                    Picker("Şununla birleştir", selection: $mergeTargetID) {
                        Text("Seç").tag(PersistentIdentifier?.none)
                        ForEach(mergeCandidates) { candidate in
                            Text(candidate.name.isEmpty ? "(adsız)" : candidate.name)
                                .tag(PersistentIdentifier?.some(candidate.persistentModelID))
                        }
                    }

                    Button("Birleştir", action: merge)
                        .disabled(mergeTarget == nil)
                } header: {
                    Text("Birleştir")
                } footer: {
                    Text("Bu etiketin bütün oturumları seçilen etikete taşınır, sonra bu etiket silinir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tag.name.isEmpty ? "(adsız etiket)" : tag.name)
        .navigationSubtitle("\(tag.lectures.count) oturum")
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: "Bu etiket silinsin mi?",
                    explanation: "Oturumlar silinmez — yalnızca bu etiket onlardan kalkar."
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
