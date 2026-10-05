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

    /// Files belong to a stored lecture. The new-lecture sheet works on a
    /// lecture that is not inserted yet, so it leaves this off and you attach
    /// files once the record exists.
    var showsFiles = false

    @Environment(\.modelContext) private var context

    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Instructor.name) private var instructors: [Instructor]
    @Query(sort: \Committee.name) private var committees: [Committee]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    var body: some View {
        Form {
            Section("Ders ve konu") {
                // The course list is small and stable — eight or so for a
                // year — so every one of them is a button. Searching for
                // something you can see is wasted work.
                if courses.isEmpty {
                    Text("Henüz ders yok. Aşağıdan ekle.")
                        .foregroundStyle(.secondary)
                } else {
                    CourseQuickPick(
                        courses: courses,
                        selectedID: lecture.course?.persistentModelID,
                        pick: { pick(course: $0) }
                    )
                }

                NameSuggestField(
                    placeholder: "Yeni ders ekle — Anatomi, Biyofizik…",
                    suggestions: courses.map(\.name)
                ) { name in
                    lecture.course = context.findOrCreateCourse(named: name)
                }

                TextField("Konu", text: $lecture.title, prompt: Text("O günün konusu"))
            }

            Section("Zaman") {
                DatePicker("Tarih", selection: dayBinding, displayedComponents: .date)

                SlotPicker(
                    startMinutes: $lecture.startMinutes,
                    endMinutes: $lecture.endMinutes
                )

                // The timetable covers almost everything, so the two clocks
                // are folded away for the exceptions: a seminar, an exam,
                // anything that does not sit on a period.
                DisclosureGroup("Saati elle ayarla") {
                    Toggle(
                        "Başlangıç saati",
                        isOn: hasTimeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart)
                    )
                    if lecture.startMinutes != nil {
                        DatePicker(
                            "Başlangıç",
                            selection: timeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle(
                        "Bitiş saati",
                        isOn: hasTimeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd)
                    )
                    if lecture.endMinutes != nil {
                        DatePicker(
                            "Bitiş",
                            selection: timeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }

            Section("Akademisyen") {
                currentValue(lecture.instructor?.displayName, color: .accentColor) {
                    lecture.instructor = nil
                }

                NameSuggestField(
                    placeholder: "Akademisyen ara veya yeni ekle",
                    suggestions: instructors.map(\.name)
                ) { name in
                    let instructor = context.findOrCreateInstructor(named: name)
                    lecture.instructor = instructor

                    // Instructor -> course is many-to-one, so it can be filled
                    // in from who is teaching. Only when the course is still
                    // empty: a choice already made is never overwritten.
                    if lecture.course == nil {
                        lecture.course = instructor?.dominantCourse
                    }
                }
            }

            Section("Komite") {
                currentValue(
                    lecture.committee?.shortLabel,
                    color: Color(hex: lecture.committee?.colorHex ?? "")
                ) {
                    lecture.committee = nil
                }

                // Says so rather than changing it: an exception may well be
                // deliberate — a make-up lecture, a seminar outside the block.
                if let suggestion = committeeSuggestion {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("Bu tarih \(suggestion.shortLabel) aralığında")
                            .font(.caption)

                        Spacer()

                        Button("Uygula") {
                            lecture.committee = suggestion
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                NameSuggestField(
                    placeholder: "Komite ara veya yeni ekle",
                    suggestions: committees.map(\.name)
                ) { name in
                    lecture.committee = context.findOrCreateCommittee(named: name)
                }
            }

            Section {
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
            } header: {
                Text("Etiketler")
            } footer: {
                Text("Dersleri enine kesen serbest konular: membran, sınavda çıktı, klinik korelasyon…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notlar") {
                TextEditor(text: $lecture.notes)
                    .font(.body)
                    .frame(minHeight: 100)
            }

            if showsFiles {
                LectureFilesSection(lecture: lecture)
            }
        }
        .formStyle(.grouped)
    }

    private var sortedTags: [Tag] {
        lecture.tags.sorted { $0.name < $1.name }
    }

    /// The single value a section currently holds, with a way to clear it.
    @ViewBuilder
    private func currentValue(
        _ text: String?,
        color: Color,
        clear: @escaping () -> Void
    ) -> some View {
        if let text, !text.isEmpty {
            HStack {
                Chip(text: text, color: color, onRemove: clear)
                Spacer()
            }
        } else {
            Text("Yok")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    /// Keeps `date` holding the day only; times live in their own fields.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { lecture.date },
            set: { newDate in
                lecture.date = Calendar.current.startOfDay(for: newDate)

                // An empty committee follows the date. One already chosen is
                // left alone; the Komite section points out the disagreement.
                if lecture.committee == nil {
                    lecture.committee = context.committee(covering: lecture.date)
                }
            }
        )
    }

    /// The committee the date implies, when that is not the one already set.
    private var committeeSuggestion: Committee? {
        guard let covering = context.committee(covering: lecture.date) else { return nil }
        return covering.persistentModelID == lecture.committee?.persistentModelID ? nil : covering
    }

    /// Tapping the selected course again clears it.
    private func pick(course: Course) -> Void {
        if lecture.course?.persistentModelID == course.persistentModelID {
            lecture.course = nil
        } else {
            lecture.course = course
        }
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

/// Every course as a button. Small, fixed set — one tap beats typing.
private struct CourseQuickPick: View {
    let courses: [Course]
    let selectedID: PersistentIdentifier?
    let pick: (Course) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(courses) { course in
                CourseChip(
                    course: course,
                    isSelected: course.persistentModelID == selectedID,
                    pick: { pick(course) }
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CourseChip: View {
    let course: Course
    let isSelected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: course.colorHex))
                    .frame(width: 7, height: 7)

                Text(course.name.isEmpty ? "(adsız)" : course.name)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color(hex: course.colorHex).opacity(0.38)
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Seçimi kaldır" : course.name)
    }
}
