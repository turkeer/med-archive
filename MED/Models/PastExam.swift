import Foundation
import SwiftData

/// Which language a paper was set in. Committees run in both, and which one
/// you are revising from matters.
enum ExamLanguage: String, Codable, CaseIterable, Identifiable {
    case turkish
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turkish: return L.pick("Türkçe", "Turkish")
        case .english: return L.pick("İngilizce", "English")
        }
    }

    var badge: String {
        switch self {
        case .turkish: return "TR"
        case .english: return "EN"
        }
    }
}

/// A past paper for a committee: last year's exam, and the years before it.
///
/// Belongs to a committee, because that is what you revise for and where you
/// go looking. Its files are ordinary `LectureFile` records — the same path
/// handling, the same preview, the same "never copies anything" promise.
@Model
final class PastExam {
    /// The academic year the paper is from, as its starting year. See
    /// `AcademicYear`.
    var startYear: Int = 2024

    var language: ExamLanguage = ExamLanguage.turkish

    var notes: String = ""
    var addedAt: Date = Date()

    var committee: Committee?

    /// Deleting a past paper deletes its file records. The files on disk are
    /// untouched, as everywhere else.
    @Relationship(deleteRule: .cascade, inverse: \LectureFile.exam)
    var files: [LectureFile] = []

    init(
        startYear: Int = AcademicYear.startYear(),
        language: ExamLanguage = .turkish,
        committee: Committee? = nil
    ) {
        self.startYear = startYear
        self.language = language
        self.addedAt = Date()
        self.committee = committee
    }
}

extension PastExam {
    /// "2022-2023"
    var yearLabel: String {
        AcademicYear.label(startYear: startYear)
    }

    /// "2022-2023 · Türkçe"
    var title: String {
        "\(yearLabel) · \(language.title)"
    }
}
