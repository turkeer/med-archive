import Foundation
import SwiftData

/// An academic who gives lectures.
@Model
final class Instructor {
    var name: String = ""

    /// Academic title, e.g. "Prof. Dr.". Not the lecture title.
    var titleText: String = ""

    var department: String = ""
    var email: String = ""

    /// Deleting an instructor must not delete their lectures — the field just empties.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.instructor)
    var lectures: [Lecture] = []

    init(name: String = "", titleText: String = "", department: String = "", email: String = "") {
        self.name = name
        self.titleText = titleText
        self.department = department
        self.email = email
    }
}

extension Instructor {
    /// "Prof. Dr. Ayşe Yılmaz", or just the name when there is no title.
    var displayName: String {
        let trimmed = titleText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : "\(trimmed) \(name)"
    }


    /// The course this academic almost always teaches.
    ///
    /// Only this direction can be guessed. An academic teaches one course as a
    /// rule, so instructor -> course is many-to-one; a course is taught by
    /// several academics, so course -> instructor is one-to-many and guessing
    /// it would be wrong as often as right.
    ///
    /// Requires a clear majority rather than merely the most frequent, so one
    /// stray entry cannot decide it.
    var dominantCourse: Course? {
        let courses = lectures.compactMap(\.course)
        guard !courses.isEmpty else { return nil }

        var tally: [PersistentIdentifier: (course: Course, count: Int)] = [:]
        for course in courses {
            let id = course.persistentModelID
            tally[id] = (course, (tally[id]?.count ?? 0) + 1)
        }

        guard let best = tally.values.max(by: { $0.count < $1.count }) else { return nil }
        return Double(best.count) / Double(courses.count) >= 0.67 ? best.course : nil
    }
}
