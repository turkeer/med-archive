import SwiftUI
import SwiftData

/// An academic and the lectures they gave.
struct InstructorDetailView: View {
    @Bindable var instructor: Instructor

    @Environment(\.modelContext) private var context

    /// Offered as the department: it is always one of these.
    @Query(sort: \Course.name) private var courses: [Course]

    var body: some View {
        Form {
            Section(L.instructor) {
                TextField(L.name, text: $instructor.name, prompt: Text("Ayşe Yılmaz"))
                    .formTextField()
                TextField(L.pick("Unvan", "Title"), text: $instructor.titleText, prompt: Text("Prof. Dr."))
                    .formTextField()
                LabeledContent(L.pick("Bölüm", "Department")) {
                    if courses.isEmpty {
                        Text(L.pick(
                            "Henüz ders yok. Kenar çubuğundaki Dersler bölümünden ekle.",
                            "No courses yet. Add one in the Courses section of the sidebar."
                        ))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            QuickPickRow(
                                items: departmentItems,
                                selectedID: selectedDepartment,
                                pick: chooseDepartment
                            )

                            if let unlisted = unlistedDepartment {
                                Text(L.pick(
                                    "Kayıtlı değer listede yok: \(unlisted)",
                                    "The stored value is not one of the courses: \(unlisted)"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                TextField(L.pick("E-posta", "Email"), text: $instructor.email)
                    .formTextField()
            }

            LectureLinkList(lectures: instructor.lectures)
        }
        .formStyle(.grouped)
        .navigationTitle(instructor.name.isEmpty ? L.pick("(adsız akademisyen)", "(unnamed instructor)") : instructor.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: L.pick("Bu akademisyen silinsin mi?", "Delete this instructor?"),
                    explanation: L.pick(
                        "Oturumlar silinmez — yalnızca akademisyen alanları boşalır.",
                        "The sessions stay; only their instructor field is cleared."
                    )
                ) {
                    context.delete(instructor)
                }
            }
        }
    }

    // MARK: Department

    /// The course names as chips, the ones this academic actually teaches
    /// first: a department is nearly always the course they give.
    ///
    /// Typed by hand until now, which is how one of them ended up saying
    /// "Medical History and Ethics" while the course said "History of
    /// Medicine". A department is one of the courses, so it is picked, not
    /// written.
    private var departmentItems: [QuickPickRow<String>.Item] {
        let named = courses.filter { !$0.name.isEmpty }
        let counts = lectureCountsByCourseName

        let taught = named
            .filter { counts[$0.name] != nil }
            .sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }

        return (taught + named.filter { counts[$0.name] == nil })
            .map { QuickPickRow.Item(id: $0.name, label: $0.name, colorHex: $0.colorHex) }
    }

    private var lectureCountsByCourseName: [String: Int] {
        var result: [String: Int] = [:]

        for lecture in instructor.lectures {
            guard let name = lecture.course?.name, !name.isEmpty else { continue }
            result[name, default: 0] += 1
        }

        return result
    }

    /// Matched on the folded name, so a stored value that differs only in case
    /// or in Turkish letters still reads as the course it means — and picking
    /// it again writes the course's own spelling back.
    private var selectedDepartment: String? {
        guard !currentDepartment.isEmpty else { return nil }
        return courses.first { SearchText.sameName($0.name, currentDepartment) }?.name
    }

    /// A stored department that is not one of the courses. Shown rather than
    /// quietly dropped, so it can be seen and corrected with one tap.
    private var unlistedDepartment: String? {
        guard !currentDepartment.isEmpty, selectedDepartment == nil else { return nil }
        return currentDepartment
    }

    private var currentDepartment: String {
        instructor.department.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chooseDepartment(_ name: String?) {
        instructor.department = name ?? ""
    }

    private var subtitle: String {
        [
            instructor.department.isEmpty ? nil : instructor.department,
            L.sessionCount(instructor.lectures.count),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
