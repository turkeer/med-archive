import Foundation
import UniformTypeIdentifiers

/// Turning picked files into records, shared by the lecture files section and
/// the past papers section so the two cannot drift apart on what a path is or
/// when a file counts as already attached.
enum FileAttaching {
    /// Every file type is accepted. Slides arrive as PDF, notes come out of
    /// Goodnotes as PDF or image, and the odd handout is a Word file.
    static let allowedTypes = [UTType.item]

    /// Records for the picked files, skipping any path already present.
    ///
    /// The records come back un-inserted and unattached: the caller inserts
    /// them and sets the side of the relationship it owns.
    static func records(
        for result: Result<[URL], Error>,
        library: LibraryRoot,
        existing: [LectureFile]
    ) -> [LectureFile] {
        guard case .success(let urls) = result else { return [] }

        var taken = Set(existing.map(\.relativePath))
        var records: [LectureFile] = []

        for url in urls {
            let path = library.storedPath(for: url)
            guard !taken.contains(path) else { continue }
            taken.insert(path)

            let name = url.lastPathComponent
            records.append(
                LectureFile(
                    fileName: name,
                    relativePath: path,
                    kind: FileNaming.kind(for: name)
                )
            )
        }

        return records
    }
}
