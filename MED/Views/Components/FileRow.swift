import AppKit
import SwiftUI

/// One attached file, used by both the lecture files section and the past
/// papers section.
///
/// A missing file says so rather than failing silently when you click it: a
/// file can be moved out from under the app at any time, and the app only ever
/// remembered where it was.
struct FileRow: View {
    let file: LectureFile
    let url: URL?
    let preview: (URL) -> Void
    let remove: () -> Void

    /// Set only where the slide / note / other distinction means something.
    /// A past paper is a past paper.
    var setKind: ((LectureFileKind) -> Void)?

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
            Image(systemName: isOnDisk ? symbolName : "exclamationmark.triangle.fill")
                .foregroundStyle(isOnDisk ? Color.accentColor : Color.orange)

            Button {
                if let url, isOnDisk { preview(url) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !isOnDisk {
                        Text(L.pick("Dosya bulunamadı", "File not found"))
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
            .help(isOnDisk ? L.pick("Önizle", "Preview") : L.pick("Dosya bulunamadı", "File not found"))

            if let url, isOnDisk {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(L.showInFinder)

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help(L.pick("Varsayılan uygulamada aç", "Open in default app"))
            }

            Menu {
                if let setKind {
                    Picker(L.format, selection: kindBinding(setKind)) {
                        ForEach(LectureFileKind.allCases) { kind in
                            Text(kind.sectionTitle).tag(kind)
                        }
                    }

                    Divider()
                }

                Button(L.pick("Listeden kaldır", "Remove from list"), role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.vertical, 2)
    }

    private var symbolName: String {
        setKind == nil ? "doc.text" : file.kind.symbolName
    }

    private func kindBinding(_ set: @escaping (LectureFileKind) -> Void) -> Binding<LectureFileKind> {
        Binding(get: { file.kind }, set: set)
    }
}
