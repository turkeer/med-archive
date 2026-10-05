import AppKit
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The files attached to a lecture, grouped as Slaytlar / Notlarım / Diğer.
///
/// Nothing here copies, moves or renames anything. A `LectureFile` is a
/// pointer; removing one forgets where a file was and leaves the file alone.
struct LectureFilesSection: View {
    let lecture: Lecture

    @Environment(\.modelContext) private var context
    @Environment(LibraryRoot.self) private var library

    @State private var isImporting = false
    @State private var previewURL: URL?

    var body: some View {
        ForEach(LectureFileKind.allCases) { kind in
            if !lecture.files(of: kind).isEmpty {
                Section(kind.sectionTitle) {
                    ForEach(lecture.files(of: kind)) { file in
                        FileRow(
                            file: file,
                            url: file.url(root: library.url),
                            preview: { previewURL = $0 },
                            setKind: { file.kind = $0 },
                            remove: { remove(file) }
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
            Text("Dosyalar uygulamaya kopyalanmaz, yalnızca yerleri saklanır. Listeden kaldırmak diskteki dosyayı silmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // `.item` accepts anything: slides arrive as PDF, but notes come out of
        // Goodnotes as PDF or image, and the odd handout is a Word file.
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.item],
            allowsMultipleSelection: true
        ) { result in
            attach(result)
        }
        .quickLookPreview($previewURL)
    }

    private func attach(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        for url in urls {
            let path = library.storedPath(for: url)

            // Attaching the same file twice to one lecture is never intended.
            guard !lecture.files.contains(where: { $0.relativePath == path }) else { continue }

            let name = url.lastPathComponent
            let file = LectureFile(
                fileName: name,
                relativePath: path,
                kind: FileNaming.kind(for: name)
            )

            context.insert(file)
            lecture.files.append(file)
        }
    }

    private func remove(_ file: LectureFile) {
        lecture.files.removeAll { $0.persistentModelID == file.persistentModelID }
        context.delete(file)
    }
}

/// One attached file. A missing file says so rather than failing silently when
/// you click it.
private struct FileRow: View {
    let file: LectureFile
    let url: URL?
    let preview: (URL) -> Void
    let setKind: (LectureFileKind) -> Void
    let remove: () -> Void

    private var isOnDisk: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The folder path under the root, shown so you can tell two files with
    /// the same name apart. Absolute paths are left out — they are long and
    /// tell you less.
    private var locationText: String? {
        guard !file.relativePath.hasPrefix("/") else { return nil }
        let folder = (file.relativePath as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : folder
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOnDisk ? file.kind.symbolName : "exclamationmark.triangle.fill")
                .foregroundStyle(isOnDisk ? Color.accentColor : Color.orange)

            Button {
                if let url, isOnDisk { preview(url) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !isOnDisk {
                        Text("Dosya bulunamadı")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let locationText {
                        Text(locationText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isOnDisk)
            .help(isOnDisk ? "Önizle" : "Dosya bulunamadı")

            if let url, isOnDisk {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Finder'da göster")

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Varsayılan uygulamada aç")
            }

            Menu {
                Picker("Tür", selection: kindBinding) {
                    ForEach(LectureFileKind.allCases) { kind in
                        Text(kind.sectionTitle).tag(kind)
                    }
                }

                Divider()

                Button("Listeden kaldır", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private var kindBinding: Binding<LectureFileKind> {
        Binding(get: { file.kind }, set: setKind)
    }
}
