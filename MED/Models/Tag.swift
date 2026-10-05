import Foundation
import SwiftData

/// A subject label shared across lectures ("Biyofizik", "Membran").
///
/// `name` is unique so that the same subject cannot accumulate under two
/// spellings: inserting a tag whose name already exists updates the existing
/// row instead of creating a second one.
@Model
final class Tag {
    @Attribute(.unique) var name: String = ""
    var colorHex: String = "9AA0A6"

    /// Inverse is declared on `Lecture.tags`.
    var lectures: [Lecture] = []

    init(name: String = "", colorHex: String = "9AA0A6") {
        self.name = name
        self.colorHex = colorHex
    }
}

