import Foundation

/// Whether a session is a lecture or a lab/practical.
enum LectureFormat: String, Codable, CaseIterable, Identifiable {
    case theoretical
    case practical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theoretical: return "Teorik"
        case .practical:   return "Pratik"
        }
    }

    /// One letter, for a badge in a list row or a week-grid cell.
    var badge: String {
        switch self {
        case .theoretical: return "T"
        case .practical:   return "P"
        }
    }
}
