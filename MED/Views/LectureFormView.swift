import SwiftUI
import SwiftData

/// Stage 1 form for creating a lecture. Instructor and committee are plain
/// pickers with a "type a new one" field beside them; the autocompleting
/// combo boxes come in stage 2.
struct LectureFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Instructor.name) private var instructors: [Instructor]
    @Query(sort: \Committee.name) private var committees: [Committee]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var title = ""
    @State private var date = Date()

    @State private var hasStart = true
    @State private var startMinutes = TimeOfDay.defaultStart
    @State private var hasEnd = true
    @State private var endMinutes = TimeOfDay.defaultEnd

    @State private var notes = ""

    @State private var selectedInstructor: Instructor?
    @State private var newInstructorName = ""

    @State private var selectedCommittee: Committee?
    @State private var newCommitteeName = ""

    /// Tags are tracked by name, so the selection survives the list reloading.
    @State private var selectedTagNames: Set<String> = []
    @State private var newTagName = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Ders") {
                    TextField("Başlık", text: $title)
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)

                    Toggle("Başlangıç saati", isOn: $hasStart)
                    if hasStart {
                        DatePicker(
                            "Başlangıç",
                            selection: timeBinding($startMinutes),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle("Bitiş saati", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker(
                            "Bitiş",
                            selection: timeBinding($endMinutes),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }

                Section("Akademisyen") {
                    Picker("Seç", selection: $selectedInstructor) {
                        Text("Yok").tag(Instructor?.none)
                        ForEach(instructors) { instructor in
                            Text(instructor.displayName).tag(Instructor?.some(instructor))
                        }
                    }
                    TextField("veya yeni akademisyen adı", text: $newInstructorName)
                }

                Section("Komite") {
                    Picker("Seç", selection: $selectedCommittee) {
                        Text("Yok").tag(Committee?.none)
                        ForEach(committees) { committee in
                            Text(committee.name).tag(Committee?.some(committee))
                        }
                    }
                    TextField("veya yeni komite adı", text: $newCommitteeName)
                }

                Section("Etiketler") {
                    HStack {
                        TextField("Yeni etiket", text: $newTagName)
                            .onSubmit(addTypedTag)
                        Button("Ekle", action: addTypedTag)
                            .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if allTags.isEmpty && selectedTagNames.isEmpty {
                        Text("Henüz etiket yok.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tagNamesToShow, id: \.self) { name in
                            Toggle(name, isOn: tagBinding(name))
                        }
                    }
                }

                Section("Notlar") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(.body)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 520, height: 620)
    }

    /// Every known tag name plus any just typed in this form, de-duplicated.
    private var tagNamesToShow: [String] {
        Array(Set(allTags.map(\.name)).union(selectedTagNames)).sorted()
    }

    // MARK: Bindings

    /// Bridges a "minutes since midnight" value to the `Date` a DatePicker wants.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { TimeOfDay.date(minutes: minutes.wrappedValue, on: date) },
            set: { minutes.wrappedValue = TimeOfDay.minutes(from: $0) }
        )
    }

    private func tagBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { selectedTagNames.contains(name) },
            set: { isOn in
                if isOn {
                    selectedTagNames.insert(name)
                } else {
                    selectedTagNames.remove(name)
                }
            }
        )
    }

    // MARK: Actions

    private func addTypedTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        selectedTagNames.insert(name)
        newTagName = ""
    }

    private func save() {
        let lecture = Lecture(
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            startMinutes: hasStart ? startMinutes : nil,
            endMinutes: hasEnd ? endMinutes : nil,
            notes: notes,
            instructor: resolvedInstructor(),
            committee: resolvedCommittee(),
            tags: resolvedTags()
        )

        context.insert(lecture)
        dismiss()
    }

    /// A freshly typed name wins over the picker, so you can add and use an
    /// instructor in one go.
    private func resolvedInstructor() -> Instructor? {
        let name = newInstructorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return selectedInstructor }

        if let existing = instructors.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let instructor = Instructor(name: name)
        context.insert(instructor)
        return instructor
    }

    private func resolvedCommittee() -> Committee? {
        let name = newCommitteeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return selectedCommittee }

        if let existing = committees.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let committee = Committee(name: name)
        context.insert(committee)
        return committee
    }

    private func resolvedTags() -> [Tag] {
        selectedTagNames.map { name in
            if let existing = allTags.first(where: { $0.name == name }) {
                return existing
            }
            let tag = Tag(name: name)
            context.insert(tag)
            return tag
        }
    }
}
