import SwiftUI
import SwiftData

/// The field set for a lecture, bound straight to the model object.
///
/// One editor serves both jobs: the detail screen hands it a stored lecture
/// and every keystroke is a live edit, while the new-lecture sheet hands it a
/// not-yet-inserted lecture and saves at the end. That keeps a single
/// implementation of the fields rather than two that drift apart.
struct LectureEditor: View {
    @Bindable var lecture: Lecture

    @Environment(\.modelContext) private var context

    @Query(sort: \Instructor.name) private var instructors: [Instructor]
    @Query(sort: \Committee.name) private var committees: [Committee]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    var body: some View {
        Form {
            Section("Ders") {
                TextField("Başlık", text: $lecture.title)

                DatePicker("Tarih", selection: dayBinding, displayedComponents: .date)

                Toggle("Başlangıç saati", isOn: hasTimeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart))
                if lecture.startMinutes != nil {
                    DatePicker(
                        "Başlangıç",
                        selection: timeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart),
                        displayedComponents: .hourAndMinute
                    )
                }

                Toggle("Bitiş saati", isOn: hasTimeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd))
                if lecture.endMinutes != nil {
                    DatePicker(
                        "Bitiş",
                        selection: timeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd),
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("Akademisyen") {
                if let instructor = lecture.instructor {
                    HStack {
                        Chip(text: instructor.displayName, color: .accentColor) {
                            lecture.instructor = nil
                        }
                        Spacer()
                    }
                } else {
                    Text("Yok")
                        .foregroundStyle(.secondary)
                }

                NameSuggestField(
                    placeholder: "Akademisyen ara veya yeni ekle",
                    suggestions: instructors.map(\.name)
                ) { name in
                    lecture.instructor = context.findOrCreateInstructor(named: name)
                }
            }

            Section("Komite") {
                if let committee = lecture.committee {
                    HStack {
                        Chip(text: committee.name, color: Color(hex: committee.colorHex)) {
                            lecture.committee = nil
                        }
                        Spacer()
                    }
                } else {
                    Text("Yok")
                        .foregroundStyle(.secondary)
                }

                NameSuggestField(
                    placeholder: "Komite ara veya yeni ekle",
                    suggestions: committees.map(\.name)
                ) { name in
                    lecture.committee = context.findOrCreateCommittee(named: name)
                }
            }

            Section("Etiketler") {
                if lecture.tags.isEmpty {
                    Text("Yok")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(sortedTags) { tag in
                            Chip(text: tag.name, color: Color(hex: tag.colorHex)) {
                                remove(tag)
                            }
                        }
                    }
                }

                NameSuggestField(
                    placeholder: "Etiket ara veya yeni ekle",
                    suggestions: allTags.map(\.name)
                ) { name in
                    add(tagNamed: name)
                }
            }

            Section("Notlar") {
                TextEditor(text: $lecture.notes)
                    .font(.body)
                    .frame(minHeight: 100)
            }
        }
        .formStyle(.grouped)
    }

    private var sortedTags: [Tag] {
        lecture.tags.sorted { $0.name < $1.name }
    }

    // MARK: Bindings

    /// Keeps `date` holding the day only; times live in their own fields.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { lecture.date },
            set: { lecture.date = Calendar.current.startOfDay(for: $0) }
        )
    }

    /// Turns "has a time at all" into a toggle over the optional minutes field.
    private func hasTimeBinding(
        for keyPath: ReferenceWritableKeyPath<Lecture, Int?>,
        default fallback: Int
    ) -> Binding<Bool> {
        Binding(
            get: { lecture[keyPath: keyPath] != nil },
            set: { lecture[keyPath: keyPath] = $0 ? fallback : nil }
        )
    }

    /// Bridges minutes-since-midnight to the `Date` a DatePicker wants.
    private func timeBinding(
        for keyPath: ReferenceWritableKeyPath<Lecture, Int?>,
        default fallback: Int
    ) -> Binding<Date> {
        Binding(
            get: {
                TimeOfDay.date(
                    minutes: lecture[keyPath: keyPath] ?? fallback,
                    on: lecture.date
                )
            },
            set: { lecture[keyPath: keyPath] = TimeOfDay.minutes(from: $0) }
        )
    }

    // MARK: Tags

    private func add(tagNamed name: String) {
        guard let tag = context.findOrCreateTag(named: name) else { return }
        guard !lecture.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) else { return }
        lecture.tags.append(tag)
    }

    private func remove(_ tag: Tag) {
        lecture.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
    }
}
