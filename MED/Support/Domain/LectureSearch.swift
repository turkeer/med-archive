import Foundation

/// Free-text matching over a lecture, Turkish-aware through `SearchText`.
///
/// One definition of "this lecture matches", shared by the search box inside a
/// related screen's list and by the Arama section. Keeping it in one place
/// means the two cannot disagree about what a hit is.
enum LectureSearch {
    /// Everything worth searching: the topic, the course, the academic, the
    /// committee, the tags, the notes and the file names — plus, when
    /// `slideHits` is given, what the slides themselves say.
    ///
    /// `slideHits` is the set of stored paths whose slide text matches, worked
    /// out once per search by `SlideIndex` rather than asked per lecture. The
    /// default of `[]` keeps every caller that has no index, and means a
    /// missing index quietly narrows the search instead of breaking it.
    static func matches(_ lecture: Lecture, query: String, slideHits: Set<String> = []) -> Bool {
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

        if lecture.files.contains(where: { SearchText.contains($0.fileName, query: needle) }) {
            return true
        }

        return !slideHits.isEmpty && lecture.files.contains { slideHits.contains($0.relativePath) }
    }
}
