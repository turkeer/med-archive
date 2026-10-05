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
            title: "Dersler",
            items: courses,
            selection: $selection,
            name: { $0.name },
            subtitle: { "\($0.lectures.count) oturum" },
            accent: { Color(hex: $0.colorHex) },
            make: { Course(colorHex: Palette.suggested(for: courses.count)) },
            emptyMessage: "Henüz ders yok.",
            addLabel: "Yeni ders"
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
            SelectionPlaceholder(text: "Ortadaki listeden bir ders seç.")
        }
    }
}

// MARK: - Akademisyenler

struct InstructorListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Instructor.name) private var instructors: [Instructor]

    var body: some View {
        NameListColumn(
            title: "Akademisyenler",
            items: instructors,
            selection: $selection,
            name: { $0.displayName },
            subtitle: {
                $0.department.isEmpty
                    ? "\($0.lectures.count) oturum"
                    : "\($0.department) · \($0.lectures.count) oturum"
            },
            accent: { _ in nil },
            make: { Instructor() },
            emptyMessage: "Henüz akademisyen yok.",
            addLabel: "Yeni akademisyen"
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
            SelectionPlaceholder(text: "Ortadaki listeden bir akademisyen seç.")
        }
    }
}

// MARK: - Komiteler

struct CommitteeListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Committee.startDate) private var committees: [Committee]

    var body: some View {
        NameListColumn(
            title: "Komiteler",
            items: committees,
            selection: $selection,
            name: { $0.name },
            subtitle: { $0.dateRangeText },
            accent: { Color(hex: $0.colorHex) },
            make: { Committee(colorHex: Palette.suggested(for: committees.count)) },
            emptyMessage: "Henüz komite yok.",
            addLabel: "Yeni komite"
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
            SelectionPlaceholder(text: "Ortadaki listeden bir komite seç.")
        }
    }
}

// MARK: - Etiketler

struct TagListColumn: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Tag.name) private var tags: [Tag]

    var body: some View {
        NameListColumn(
            title: "Etiketler",
            items: tags,
            selection: $selection,
            name: { $0.name },
            subtitle: { "\($0.lectures.count) oturum" },
            accent: { Color(hex: $0.colorHex) },
            make: { Tag(colorHex: Palette.suggested(for: tags.count)) },
            emptyMessage: "Henüz etiket yok.",
            addLabel: "Yeni etiket"
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
            SelectionPlaceholder(text: "Ortadaki listeden bir etiket seç.")
        }
    }
}

// MARK: - Ortak

struct SelectionPlaceholder: View {
    let text: String

    var body: some View {
        ContentUnavailableView(
            "Seçim yok",
            systemImage: "sidebar.left",
            description: Text(text)
        )
    }
}
