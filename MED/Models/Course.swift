import Foundation
import SwiftData

/// A course that recurs through the curriculum: Anatomi, Biyofizik, Tıbbi Biyoloji.
///
/// Deliberately not tied to a committee. The same course runs across more than
/// one committee, and the folder layout allows exactly that — both
/// `Komite I/Biyofizik/` and `Komite II/Biyofizik/` map to this one record.
///
/// This is the structural level above a lecture, mirroring the course folder
/// on disk. Free-form labels that cut across courses belong in `Tag`.
@Model
final class Course {
    var name: String = ""

    /// Six-digit hex, no leading "#".
    var colorHex: String = "D98A4F"

    /// Deleting a course must not delete its lectures — the field just empties.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.course)
    var lectures: [Lecture] = []

    init(name: String = "", colorHex: String = "D98A4F") {
        self.name = name
        self.colorHex = colorHex
    }
}

