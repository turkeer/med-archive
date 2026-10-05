import QuickLook
import SwiftData
import SwiftUI

/// The files attached to a lecture, grouped as Slaytlar / Notlarım / Diğer.
///
/// Files are shown for the whole **topic**, not just this record. One subject
/// taught across two periods is two lectures but one set of slides — the
/// break in the middle does not hand out a second handout. So a file attached
/// to either part shows from both, and attaching from here attaches to the
/// part you are looking at.
///
/// Nothing here copies, moves or renames anything. A `LectureFile` is a
/// pointer; removing one forgets where a file was and leaves the file alone.
struct LectureFilesSection: View {
    let lecture: Lecture

    @Environment(\.modelContext) private var context
    @Environment(LibraryRoot.self) private var library

    @Query private var allLectures: [Lecture]

    @State private var isImporting = false
    @State private var previewURL: URL?

    /// The lectures that are parts of this topic, this one included.
    private var parts: [Lecture] {
        LectureGrouping.parts(of: lecture, among: allLectures)
    }

    /// Every part's files of one kind, together.
    private func files(of kind: LectureFileKind) -> [LectureFile] {
        parts
            .flatMap { $0.files(of: kind) }
            .sorted { $0.fileName < $1.fileName }
    }

    var body: some View {
        ForEach(LectureFileKind.allCases) { kind in
            if !files(of: kind).isEmpty {
                Section(kind.sectionTitle) {
                    ForEach(files(of: kind)) { file in
                        FileRow(
                            file: file,
                            url: file.url(root: library.url),
                            preview: { previewURL = $0 },
                            remove: { remove(file) },
                            setKind: { file.kind = $0 }
                        )
                    }
                }
            }
        }

        Section {
            Button {
                isImporting = true
            } label: {
                Label("Dosya ekle", systemImage: "paperclip")
            }

            if library.url == nil {
                Text("Kök klasör seçilmedi. Ayarlar'dan (⌘,) seçersen dosyalar klasöre göre kaydedilir ve klasörü taşısan da bağlar kopmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dosyalar")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if parts.count > 1 {
                    Text("Bu konu \(parts.count) ders olarak işleniyor. Dosyalar tek bir derse değil, konunun tamamına ait sayılıyor — her parçadan aynı liste görünür.")
                }

                Text("Dosyalar uygulamaya kopyalanmaz, yalnızca yerleri saklanır. Listeden kaldırmak diskteki dosyayı silmez.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: FileAttaching.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            attach(result)
        }
        .quickLookPreview($previewURL)
    }

    private func attach(_ result: Result<[URL], Error>) {
        // Dedup against the whole topic, not just this record.
        let existing = parts.flatMap(\.files)

        for file in FileAttaching.records(for: result, library: library, existing: existing) {
            context.insert(file)
            lecture.files.append(file)
        }
    }

    /// The file may belong to another part of the topic, so it is detached
    /// from whichever lecture actually holds it.
    private func remove(_ file: LectureFile) {
        if let owner = file.lecture {
            owner.files.removeAll { $0.persistentModelID == file.persistentModelID }
        }
        context.delete(file)
    }
}
