import Foundation

/// What kind of session this is.
///
/// An exam lives here rather than on a tag because it is the same kind of fact
/// as "this is a lab": one answer per session, always present, and the thing
/// you filter a list by. A tag would make it optional, misspellable and
/// invisible to the type filter.
enum LectureFormat: String, Codable, CaseIterable, Identifiable {
    case theoretical
    case practical
    case exam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theoretical: return "Teorik"
        case .practical:   return "Pratik"
        case .exam:        return "Sınav"
        }
    }

    /// One letter, for a badge in a list row or a week-grid cell.
    var badge: String {
        switch self {
        case .theoretical: return "T"
        case .practical:   return "P"
        case .exam:        return "S"
        }
    }
}
