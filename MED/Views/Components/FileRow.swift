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

    /// Left out where the row is only for reading. Opening, previewing and
    /// revealing stay — they are what you came for; taking the record away is
    /// the part that belongs to editing.
    var remove: (() -> Void)?

    /// Set only where the slide / note / other distinction means something.
    /// A past paper is a past paper.
    var setKind: ((LectureFileKind) -> Void)?

    /// Set for files the app can read itself (PDFs): opens the file in the
    /// in-app viewer, where a term can be selected and looked up. Left unset
    /// for anything else, which has nothing but Quick Look and the default app.
    var openInApp: (() -> Void)?

    /// Opens the same in-app viewer filling the whole window. Set alongside
    /// `openInApp`.
    var openFullScreen: (() -> Void)?

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
                if let openInApp {
                    Button(action: openInApp) {
                        Image(systemName: "text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help(L.pick("Uygulamada oku (kelime seçip ara)", "Read in the app (select a word to look it up)"))
                }

                // Finder and "open in the default app" are rarely wanted, so
                // they sit under the menu rather than taking two slots in every
                // row. Editing adds its own items to the same menu.
                Menu {
                    if let openFullScreen {
                        Button {
                            openFullScreen()
                        } label: {
                            Label(L.pick("Tam ekran oku", "Read full screen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        }

                        Divider()
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label(L.showInFinder, systemImage: "folder")
                    }

                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(L.pick("Varsayılan uygulamada aç", "Open in default app"), systemImage: "arrow.up.forward.app")
                    }

                    if setKind != nil || remove != nil {
                        Divider()
                    }

                    if let setKind {
                        Picker(L.format, selection: kindBinding(setKind)) {
                            ForEach(LectureFileKind.allCases) { kind in
                                Text(kind.sectionTitle).tag(kind)
                            }
                        }
                    }

                    if let remove {
                        Button(L.pick("Listeden kaldır", "Remove from list"), role: .destructive, action: remove)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
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
