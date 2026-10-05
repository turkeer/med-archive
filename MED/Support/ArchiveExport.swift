import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The whole archive as one readable document.
///
/// Every record carries a short id (`c1`, `i2`, `k1`, `t3`) and a lecture
/// points at those ids. `PersistentIdentifier` would have been less work and
/// no use at all outside this app: it is opaque, and a backup you cannot read
/// is a backup you cannot check.
///
/// Derived fields that cost nothing — a committee's label, a lecture's period
/// range — are written out too. The point of the file is to be legible without
/// the app that wrote it.
struct ArchiveSnapshot: Codable {
    /// Bumped when the shape changes, so a later reader knows what it has.
    var schema = 1

    var exportedAt = Date()

    var courses: [CourseRecord] = []
    var instructors: [InstructorRecord] = []
    var committees: [CommitteeRecord] = []
    var tags: [TagRecord] = []
    var lectures: [LectureRecord] = []
}

struct CourseRecord: Codable {
    var id: String
    var name: String
    var colorHex: String
}

struct InstructorRecord: Codable {
    var id: String
    var name: String
    var title: String
    var department: String
    var email: String
}

struct CommitteeRecord: Codable {
    var id: String
    var name: String
    var code: String
    var label: String
    var startDate: Date
    var endDate: Date
    var colorHex: String
    var pastExams: [PastExamRecord]
}

struct PastExamRecord: Codable {
    var academicYear: String
    var startYear: Int
    var language: String
    var notes: String
    var addedAt: Date
    var files: [FileRecord]
}

struct TagRecord: Codable {
    var id: String
    var name: String
    var colorHex: String
}

struct FileRecord: Codable {
    var fileName: String

    /// As stored: relative to the library root, or absolute when the file was
    /// picked from outside it.
    var path: String

    var kind: String
    var addedAt: Date
}

struct LectureRecord: Codable {
    var title: String
    var date: Date
    var startMinutes: Int?
    var endMinutes: Int?

    /// "2.–3. ders" — derived, and the reason the minute counts are legible.
    var slots: String

    var format: String
    var notes: String
    var createdAt: Date

    var courseID: String?
    var instructorID: String?
    var committeeID: String?
    var tagIDs: [String]
    var files: [FileRecord]
}

/// Writing the archive out as JSON.
///
/// Export only, deliberately. Reading a file back in means deciding what to do
/// about every record that already exists — merge, replace, duplicate — and
/// getting that wrong silently doubles an archive. The real restore path is
/// the store file itself, which Settings points at; this file is for reading,
/// checking and carrying the data somewhere else.
enum ArchiveExport {
    static func snapshot(from context: ModelContext) -> ArchiveSnapshot {
        let courses = fetch(Course.self, from: context)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let instructors = fetch(Instructor.self, from: context)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let committees = fetch(Committee.self, from: context)
            .sorted { $0.startDate < $1.startDate }
        let tags = fetch(Tag.self, from: context)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let lectures = fetch(Lecture.self, from: context)
            .sorted { LectureSort.oldestFirst.precedes($0, $1) }

        let courseIDs = identifiers(for: courses, prefix: "c")
        let instructorIDs = identifiers(for: instructors, prefix: "i")
        let committeeIDs = identifiers(for: committees, prefix: "k")
        let tagIDs = identifiers(for: tags, prefix: "t")

        var snapshot = ArchiveSnapshot()

        snapshot.courses = courses.map { course in
            CourseRecord(
                id: courseIDs[course.persistentModelID] ?? "",
                name: course.name,
                colorHex: course.colorHex
            )
        }

        snapshot.instructors = instructors.map { instructor in
            InstructorRecord(
                id: instructorIDs[instructor.persistentModelID] ?? "",
                name: instructor.name,
                title: instructor.titleText,
                department: instructor.department,
                email: instructor.email
            )
        }

        snapshot.committees = committees.map { committee in
            CommitteeRecord(
                id: committeeIDs[committee.persistentModelID] ?? "",
                name: committee.name,
                code: committee.code,
                label: committee.fullLabel,
                startDate: committee.startDate,
                endDate: committee.endDate,
                colorHex: committee.colorHex,
                pastExams: committee.pastExams
                    .sorted { $0.startYear > $1.startYear }
                    .map(exam)
            )
        }

        snapshot.tags = tags.map { tag in
            TagRecord(
                id: tagIDs[tag.persistentModelID] ?? "",
                name: tag.name,
                colorHex: tag.colorHex
            )
        }

        snapshot.lectures = lectures.map { lecture in
            LectureRecord(
                title: lecture.title,
                date: lecture.date,
                startMinutes: lecture.startMinutes,
                endMinutes: lecture.endMinutes,
                slots: LectureGrouping.slotLabel(for: [lecture]),
                format: lecture.format.rawValue,
                notes: lecture.notes,
                createdAt: lecture.createdAt,
                courseID: lecture.course.flatMap { courseIDs[$0.persistentModelID] },
                instructorID: lecture.instructor.flatMap { instructorIDs[$0.persistentModelID] },
                committeeID: lecture.committee.flatMap { committeeIDs[$0.persistentModelID] },
                tagIDs: lecture.tags.compactMap { tagIDs[$0.persistentModelID] }.sorted(),
                files: lecture.files.sorted { $0.fileName < $1.fileName }.map(file)
            )
        }

        return snapshot
    }

    private static func exam(_ exam: PastExam) -> PastExamRecord {
        PastExamRecord(
            academicYear: exam.yearLabel,
            startYear: exam.startYear,
            language: exam.language.rawValue,
            notes: exam.notes,
            addedAt: exam.addedAt,
            files: exam.files.sorted { $0.fileName < $1.fileName }.map(file)
        )
    }

    private static func file(_ record: LectureFile) -> FileRecord {
        FileRecord(
            fileName: record.fileName,
            path: record.relativePath,
            kind: record.kind.rawValue,
            addedAt: record.addedAt
        )
    }

    private static func fetch<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func identifiers<T: PersistentModel>(
        for models: [T],
        prefix: String
    ) -> [PersistentIdentifier: String] {
        var result: [PersistentIdentifier: String] = [:]

        for (offset, model) in models.enumerated() {
            result[model.persistentModelID] = "\(prefix)\(offset + 1)"
        }

        return result
    }

    // MARK: Writing

    static func json(_ snapshot: ArchiveSnapshot) throws -> Data {
        let encoder = JSONEncoder()

        // Sorted keys and ISO dates so that two exports of the same archive
        // are the same bytes: a diff then shows what changed, rather than how
        // the dictionary happened to be ordered that day.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(snapshot)
    }

    static func defaultFileName(on day: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return "MED arşivi \(formatter.string(from: day)).json"
    }

    /// Asks where to put the file, then writes it. Does nothing if cancelled.
    static func save(from context: ModelContext) {
        let panel = NSSavePanel()
        panel.title = "Arşivi dışa aktar"
        panel.nameFieldStringValue = defaultFileName()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == NSApplication.ModalResponse.OK,
              let url = panel.url
        else { return }

        do {
            try json(snapshot(from: context)).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Dışa aktarma başarısız"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }
}
