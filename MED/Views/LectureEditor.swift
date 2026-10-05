import SwiftData
import SwiftUI

/// The field set for a lecture, bound straight to the model object.
///
/// One editor serves both jobs: the detail screen hands it a stored lecture
/// and every keystroke is a live edit, while the new-lecture sheet hands it a
/// freshly inserted one. That keeps a single implementation of the fields
/// rather than two that drift apart.
///
/// Courses, committees and academics are **chosen** here, never created.
/// Over a year there are eight or so courses and seven committees, and they
/// are set up once in their own sections — an "add" field in a form used
/// hundreds of times is clutter paid for every single time. The exception is
/// a new academic, which does come up mid-year, so that one gets a button.
struct LectureEditor: View {
    @Bindable var lecture: Lecture

    /// Files belong to a stored lecture, so the new-lecture sheet leaves this
    /// off and you attach them once the record exists.
    var showsFiles = false

    @Environment(\.modelContext) private var context

    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Instructor.name) private var instructors: [Instructor]
    @Query(sort: \Committee.startDate) private var committees: [Committee]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var isAddingInstructor = false
    @State private var newInstructorName = ""

    var body: some View {
        Form {
            Section("Ders ve konu") {
                if courses.isEmpty {
                    Text("Henüz ders yok. Kenar çubuğundaki Dersler bölümünden ekle.")
                        .foregroundStyle(.secondary)
                } else {
                    QuickPickRow(
                        items: courses.map(courseItem),
                        selectedID: lecture.course?.persistentModelID,
                        pick: chooseCourse
                    )
                }

                TextField("Konu", text: $lecture.title, prompt: Text("O günün konusu"))
                    .formTextField()

                Picker("Tür", selection: $lecture.format) {
                    ForEach(LectureFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
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
                HStack {
                    Picker("Akademisyen", selection: instructorBinding) {
                        Text("Yok").tag(Instructor?.none)
                        ForEach(instructors) { instructor in
                            Text(instructor.displayName).tag(Instructor?.some(instructor))
                        }
                    }
                    .labelsHidden()

                    Button {
                        isAddingInstructor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Yeni akademisyen")
                }
            }

            Section("Komite") {
                if committees.isEmpty {
                    Text("Henüz komite yok. Kenar çubuğundaki Komiteler bölümünden ekle.")
                        .foregroundStyle(.secondary)
                } else {
                    QuickPickRow(
                        items: committees.map(committeeItem),
                        selectedID: lecture.committee?.persistentModelID,
                        pick: chooseCommittee
                    )
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

                // Tags are the one thing genuinely created as you go, so this
                // field stays.
                NameSuggestField(
                    placeholder: "Etiket ara veya yeni ekle",
                    suggestions: allTags.map(\.name)
                ) { name in
                    add(tagNamed: name)
                }
            } header: {
                Text("Etiketler")
            } footer: {
                Text("Oturumları enine kesen serbest konular: membran, sınavda çıktı, klinik korelasyon…")
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
        .alert("Yeni akademisyen", isPresented: $isAddingInstructor) {
            TextField("Ad", text: $newInstructorName)
                .formTextField()

            Button("Ekle", action: addInstructor)
            Button("Vazgeç", role: .cancel) {
                newInstructorName = ""
            }
        }
    }

    private var sortedTags: [Tag] {
        lecture.tags.sorted { $0.name < $1.name }
    }

    // MARK: Choosing

    private func courseItem(_ course: Course) -> QuickPickRow.Item {
        QuickPickRow.Item(
            id: course.persistentModelID,
            label: course.name.isEmpty ? "(adsız)" : course.name,
            colorHex: course.colorHex
        )
    }

    private func committeeItem(_ committee: Committee) -> QuickPickRow.Item {
        QuickPickRow.Item(
            id: committee.persistentModelID,
            label: committee.shortLabel.isEmpty ? "(adsız)" : committee.shortLabel,
            colorHex: committee.colorHex
        )
    }

    private func chooseCourse(_ id: PersistentIdentifier?) {
        lecture.course = id.flatMap { target in
            courses.first { $0.persistentModelID == target }
        }
    }

    private func chooseCommittee(_ id: PersistentIdentifier?) {
        lecture.committee = id.flatMap { target in
            committees.first { $0.persistentModelID == target }
        }
    }

    /// Choosing an academic fills in the course when it is still empty.
    /// Instructor -> course is many-to-one, so it can be guessed; a choice
    /// already made is never overwritten.
    private var instructorBinding: Binding<Instructor?> {
        Binding(
            get: { lecture.instructor },
            set: { chosen in
                lecture.instructor = chosen
                if lecture.course == nil {
                    lecture.course = chosen?.dominantCourse
                }
            }
        )
    }

    private func addInstructor() {
        let instructor = context.findOrCreateInstructor(named: newInstructorName)
        newInstructorName = ""

        guard let instructor else { return }
        lecture.instructor = instructor

        if lecture.course == nil {
            lecture.course = instructor.dominantCourse
        }
    }

    // MARK: Bindings

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
