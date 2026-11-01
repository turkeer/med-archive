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
    @Query private var allLectures: [Lecture]

    @State private var isAddingInstructor = false
    @State private var newInstructorName = ""
    @State private var isLinkingTopic = false

    var body: some View {
        Form {
            Section(L.pick("Ders ve konu", "Course and topic")) {
                if courses.isEmpty {
                    Text(L.pick(
                        "Henüz ders yok. Kenar çubuğundaki Dersler bölümünden ekle.",
                        "No courses yet. Add one in the Courses section of the sidebar."
                    ))
                        .foregroundStyle(.secondary)
                } else {
                    QuickPickRow(
                        items: courses.map(courseItem),
                        selectedID: lecture.course?.persistentModelID,
                        pick: chooseCourse
                    )
                }

                TextField(L.topic, text: $lecture.title, prompt: Text(L.pick("O günün konusu", "That day's topic")))
                    .formTextField()

                Picker(L.format, selection: $lecture.format) {
                    ForEach(LectureFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L.pick("Zaman", "Time")) {
                DatePicker(L.pick("Tarih", "Date"), selection: dayBinding, displayedComponents: .date)

                SlotPicker(
                    startMinutes: $lecture.startMinutes,
                    endMinutes: $lecture.endMinutes
                )

                // The timetable covers almost everything, so the two clocks
                // are folded away for the exceptions: a seminar, an exam,
                // anything that does not sit on a period.
                DisclosureGroup(L.pick("Saati elle ayarla", "Set the time by hand")) {
                    Toggle(
                        L.pick("Başlangıç saati", "Start time"),
                        isOn: hasTimeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart)
                    )
                    if lecture.startMinutes != nil {
                        DatePicker(
                            L.pick("Başlangıç", "Starts"),
                            selection: timeBinding(for: \.startMinutes, default: TimeOfDay.defaultStart),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle(
                        L.pick("Bitiş saati", "End time"),
                        isOn: hasTimeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd)
                    )
                    if lecture.endMinutes != nil {
                        DatePicker(
                            L.pick("Bitiş", "Ends"),
                            selection: timeBinding(for: \.endMinutes, default: TimeOfDay.defaultEnd),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }

            // A subject taught over two periods of one day groups itself; this
            // is for the other case — the same subject continued on another
            // day — which can only be said by hand. Only when editing a stored
            // lecture (the new-lecture sheet has no record to link to yet).
            if showsFiles {
                Section {
                    ForEach(otherDays, id: \.day) { entry in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.lectures.first?.displayTitle ?? L.untitled)
                                Text(dayLine(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                if let member = entry.lectures.first {
                                    LectureGrouping.detachDay(of: member, among: allLectures)
                                }
                            } label: {
                                Image(systemName: "link.badge.minus")
                            }
                            .buttonStyle(.borderless)
                            .help(L.pick("Bu günü konudan ayır", "Remove this day from the topic"))
                        }
                    }

                    Button {
                        isLinkingTopic = true
                    } label: {
                        Label(
                            otherDays.isEmpty
                                ? L.pick("Başka bir güne bağla…", "Link across days…")
                                : L.pick("Başka gün ekle…", "Add another day…"),
                            systemImage: "link"
                        )
                    }
                } header: {
                    Text(L.pick("Konu devamlılığı", "Topic continuity"))
                } footer: {
                    Text(L.pick(
                        "Farklı günlere yayılan tek bir konuyu birleştir: tüm dersler birlikte numaralanır ve slaytları ortak olur.",
                        "Join one subject spread over several days: the lessons are numbered together and share their slides."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L.instructor) {
                HStack {
                    Picker(L.instructor, selection: instructorBinding) {
                        Text(L.none).tag(Instructor?.none)
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
                    .help(L.newInstructor)
                }
            }

            Section(L.committee) {
                if committees.isEmpty {
                    Text(L.pick(
                        "Henüz komite yok. Kenar çubuğundaki Komiteler bölümünden ekle.",
                        "No committees yet. Add one in the Committees section of the sidebar."
                    ))
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

                        Text(L.pick(
                            "Bu tarih \(suggestion.shortLabel) aralığında",
                            "This date falls inside \(suggestion.shortLabel)"
                        ))
                            .font(.caption)

                        Spacer()

                        Button(L.apply) {
                            lecture.committee = suggestion
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            Section {
                if lecture.tags.isEmpty {
                    Text(L.none)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(sortedTags) { tag in
                            Chip(text: tag.name, color: Color(hex: tag.colorHex)) {
                                remove(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Tags are the one thing genuinely created as you go, so this
                // field stays.
                NameSuggestField(
                    placeholder: L.pick("Etiket ara veya yeni ekle", "Search tags or add a new one"),
                    suggestions: allTags.map(\.name)
                ) { name in
                    add(tagNamed: name)
                }
            } header: {
                Text(L.tags)
            } footer: {
                Text(L.pick(
                    "Oturumları enine kesen serbest konular: membran, sınavda çıktı, klinik korelasyon…",
                    "Free-form themes that cut across sessions: membrane, came up in the exam, clinical correlation…"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.notes) {
                TextEditor(text: $lecture.notes)
                    .font(.body)
                    .frame(minHeight: 100)
            }

            if showsFiles {
                LectureFilesSection(lecture: lecture)
            }
        }
        .formStyle(.grouped)
        .alert(L.newInstructor, isPresented: $isAddingInstructor) {
            TextField(L.name, text: $newInstructorName)
                .formTextField()

            Button(L.add, action: addInstructor)
            Button(L.cancel, role: .cancel) {
                newInstructorName = ""
            }
        }
        .sheet(isPresented: $isLinkingTopic) {
            TopicLinkSheet(lecture: lecture)
        }
    }

    private var sortedTags: [Tag] {
        lecture.tags.sorted { $0.name < $1.name }
    }

    // MARK: Topic continuity

    /// One day of the topic other than this lecture's own: its lessons, grouped
    /// so a day is added or removed as a unit.
    private struct TopicDay {
        let day: Date
        let lectures: [Lecture]
    }

    /// The topic's other days, earliest first. This lecture's own day is left
    /// out: it is where you are, not something to add or detach.
    private var otherDays: [TopicDay] {
        let ownDay = Calendar.current.startOfDay(for: lecture.date)
        let grouped = Dictionary(grouping: LectureGrouping.parts(of: lecture, among: allLectures)) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped
            .filter { $0.key != ownDay }
            .map { TopicDay(day: $0.key, lectures: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private func dayLine(for entry: TopicDay) -> String {
        let day = L.format(entry.day, Date.FormatStyle.dateTime.weekday(.abbreviated).day().month())
        return "\(day) · \(LectureGrouping.slotLabel(for: entry.lectures))"
    }

    // MARK: Choosing

    private func courseItem(_ course: Course) -> QuickPickRow<PersistentIdentifier>.Item {
        QuickPickRow.Item(
            id: course.persistentModelID,
            label: course.name.isEmpty ? L.unnamed : course.name,
            colorHex: course.colorHex
        )
    }

    private func committeeItem(_ committee: Committee) -> QuickPickRow<PersistentIdentifier>.Item {
        QuickPickRow.Item(
            id: committee.persistentModelID,
            label: committee.shortLabel.isEmpty ? L.unnamed : committee.shortLabel,
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
