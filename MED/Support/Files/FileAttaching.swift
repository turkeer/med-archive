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
            // macOS: dosya olduğu yerde referans edilir. iOS: konteynere bir
            // kopya alınır ve yol o kopyaya göre hesaplanır.
            guard let fileURL = library.prepareForAttach(url) else { continue }

            let path = library.storedPath(for: fileURL)
            guard !taken.contains(path) else { continue }
            taken.insert(path)

            let name = fileURL.lastPathComponent
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

    #if os(iOS)
    /// iOS: `records` ile aynı iş, ama .pptx dosyalarını önce cihazda PDF'e
    /// çevirir ve yalnızca PDF'i konteynere alır (orijinal pptx saklanmaz).
    /// Dönüşüm başarısız olursa pptx olduğu gibi eklenir — veri kaybı olmaz.
    static func records(
        for result: Result<[URL], Error>,
        library: LibraryRoot,
        existing: [LectureFile],
        converter: PptxConverter
    ) async -> [LectureFile] {
        guard case .success(let urls) = result else { return [] }

        var taken = Set(existing.map(\.relativePath))
        var records: [LectureFile] = []

        for url in urls {
            // .pptx ise cihazda PDF'e çevir; başarısızsa orijinale düş.
            var attachSource = url
            var tempToClean: URL?
            if url.pathExtension.lowercased() == "pptx" {
                if let pdf = try? await converter.convert(pptx: url) {
                    attachSource = pdf
                    tempToClean = pdf
                }
            }

            guard let fileURL = library.prepareForAttach(attachSource) else {
                if let t = tempToClean { try? FileManager.default.removeItem(at: t) }
                continue
            }
            if let t = tempToClean { try? FileManager.default.removeItem(at: t) }

            let path = library.storedPath(for: fileURL)
            guard !taken.contains(path) else { continue }
            taken.insert(path)

            let name = fileURL.lastPathComponent
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
    #endif
}
