import SwiftUI
import SwiftData

// The middle and trailing columns for the four related sections. Each pair is
// plumbing only: the list column owns the query, and the detail column
// resolves the selected id back to a record, falling back to a placeholder
// when that record is gone — which is how deletion is handled throughout.

// MARK: - Dersler

struct CourseListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Course.name) private var courses: [Course]

    var body: some View {
        NameListColumn(
            title: L.courses,
            items: courses,
            selection: $selection,
            name: { $0.name },
            subtitle: { L.sessionCount($0.lectures.count) },
            accent: { Color(hex: $0.colorHex) },
            make: { Course(colorHex: Palette.suggested(for: courses.count)) },
            emptyMessage: L.pick("Henüz ders yok.", "No courses yet."),
            addLabel: L.newCourse
        )
    }
}

struct CourseDetailColumn: View {
    let courseID: PersistentIdentifier?
    @Query private var courses: [Course]

    var body: some View {
        if let course = courses.first(where: { $0.persistentModelID == courseID }) {
            CourseDetailView(course: course)
        } else {
            SelectionPlaceholder(text: L.pick("Ortadaki listeden bir ders seç.", "Pick a course from the middle list."))
        }
    }
}

// MARK: - Akademisyenler

struct InstructorListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Instructor.name) private var instructors: [Instructor]

    var body: some View {
        NameListColumn(
            title: L.instructors,
            items: instructors,
            selection: $selection,
            name: { $0.displayName },
            subtitle: {
                $0.department.isEmpty
                    ? L.sessionCount($0.lectures.count)
                    : "\($0.department) · " + L.sessionCount($0.lectures.count)
            },
            accent: { _ in nil },
            make: { Instructor() },
            emptyMessage: L.pick("Henüz akademisyen yok.", "No instructors yet."),
            addLabel: L.newInstructor
        )
    }
}

struct InstructorDetailColumn: View {
    let instructorID: PersistentIdentifier?
    @Query private var instructors: [Instructor]

    var body: some View {
        if let instructor = instructors.first(where: { $0.persistentModelID == instructorID }) {
            InstructorDetailView(instructor: instructor)
        } else {
            SelectionPlaceholder(text: L.pick("Ortadaki listeden bir akademisyen seç.", "Pick an instructor from the middle list."))
        }
    }
}

// MARK: - Komiteler

struct CommitteeListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Committee.startDate) private var committees: [Committee]

    var body: some View {
        NameListColumn(
            title: L.committees,
            items: committees,
            selection: $selection,
            name: { $0.fullLabel },
            subtitle: { $0.dateRangeText },
            accent: { Color(hex: $0.colorHex) },
            make: { Committee(colorHex: Palette.suggested(for: committees.count)) },
            emptyMessage: L.pick("Henüz komite yok.", "No committees yet."),
            addLabel: L.newCommittee
        )
    }
}

struct CommitteeDetailColumn: View {
    let committeeID: PersistentIdentifier?
    @Query private var committees: [Committee]

    var body: some View {
        if let committee = committees.first(where: { $0.persistentModelID == committeeID }) {
            CommitteeDetailView(committee: committee)
        } else {
            SelectionPlaceholder(text: L.pick("Ortadaki listeden bir komite seç.", "Pick a committee from the middle list."))
        }
    }
}

// MARK: - Etiketler

struct TagListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Tag.name) private var tags: [Tag]

    var body: some View {
        NameListColumn(
            title: L.tags,
            items: tags,
            selection: $selection,
            name: { $0.name },
            subtitle: { L.sessionCount($0.lectures.count) },
            accent: { Color(hex: $0.colorHex) },
            make: { Tag(colorHex: Palette.suggested(for: tags.count)) },
            emptyMessage: L.pick("Henüz etiket yok.", "No tags yet."),
            addLabel: L.newTag
        )
    }
}

struct TagDetailColumn: View {
    let tagID: PersistentIdentifier?
    @Query private var tags: [Tag]

    var body: some View {
        if let tag = tags.first(where: { $0.persistentModelID == tagID }) {
            TagDetailView(tag: tag)
        } else {
            SelectionPlaceholder(text: L.pick("Ortadaki listeden bir etiket seç.", "Pick a tag from the middle list."))
        }
    }
}

// MARK: - Ortak

struct SelectionPlaceholder: View {
    let text: String

    var body: some View {
        ContentUnavailableView(
            L.pick("Seçim yok", "Nothing selected"),
            systemImage: "sidebar.left",
            description: Text(text)
        )
    }
}
