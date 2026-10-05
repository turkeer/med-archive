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

    var lecturesByDate: [Lecture] {
        lectures.sorted { $0.date > $1.date }
    }
}
