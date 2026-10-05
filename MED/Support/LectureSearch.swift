import Foundation

/// Free-text matching over a lecture, Turkish-aware through `SearchText`.
///
/// One definition of "this lecture matches", shared by the search box inside a
/// related screen's list and by the Arama section. Keeping it in one place
/// means the two cannot disagree about what a hit is.
enum LectureSearch {
    /// Everything worth searching: the topic, the course, the academic, the
    /// committee, the tags and the notes.
    static func matches(_ lecture: Lecture, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        let fields = [
            lecture.title,
            lecture.course?.name,
            lecture.instructor?.name,
            lecture.instructor?.titleText,
            lecture.committee?.name,
            lecture.committee?.code,
            lecture.notes,
        ]
        .compactMap { $0 }

        if fields.contains(where: { SearchText.contains($0, query: needle) }) {
            return true
        }

        if lecture.tags.contains(where: { SearchText.contains($0.name, query: needle) }) {
            return true
        }

        return lecture.files.contains { SearchText.contains($0.fileName, query: needle) }
    }
}
