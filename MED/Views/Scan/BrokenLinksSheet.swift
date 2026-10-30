import SwiftData
import SwiftUI

/// The file records that point at nothing, and two ways to settle each one.
///
/// Nothing here touches the disk. "Show its location" repoints the record at
/// the file where it is now; "Remove the record" forgets where a file was and
/// leaves the file alone — the same guarantee the rest of the app makes.
struct BrokenLinksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LibraryRoot.self) private var library

    @Query private var fileRecords: [LectureFile]

    @State private var broken: [LectureFile] = []

    /// Split in two on purpose. A synthetic `isPresented` binding whose setter
    /// clears the target would wipe it before the importer's completion
    /// handler ran, and the picked file would land nowhere — a bug this
    /// project has already shipped twice.
    @State private var isImporting = false
    @State private var repairTarget: LectureFile?

    @State private var repaired = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 420, idealHeight: 520)
        .onAppear(perform: refresh)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: FileAttaching.allowedTypes
        ) { result in
            repair(with: result)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(L.pick("Yeri değişmiş dosyalar", "Files that have moved"))
                    .font(.headline)

                Text(L.pick(
                    "Kayıt bir dosyayı gösteriyor ama orada artık bir şey yok.",
                    "The record points at a file that is no longer there."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if repaired > 0 {
                Label(
                    L.pick("\(repaired) kayıt düzeltildi", "\(repaired) records fixed"),
                    systemImage: "checkmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L.close) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if broken.isEmpty {
            ContentUnavailableView {
                Label(
                    L.pick("Bozuk bağ yok", "No broken links"),
                    systemImage: "checkmark.circle"
                )
            } description: {
                Text(L.pick(
                    "Kayıtlı bütün dosyalar yerlerinde.",
                    "Every recorded file is where the archive expects it."
                ))
            }
        } else {
            List {
                ForEach(broken) { record in
                    row(record)
                }
            }
        }
    }

    private func row(_ record: LectureFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(FileHealth.ownerText(of: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(record.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Button(L.pick("Yerini göster…", "Show its location…")) {
                repairTarget = record
                isImporting = true
            }

            Button(L.pick("Kaydı kaldır", "Remove record"), role: .destructive) {
                remove(record)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: Doing the work

    private func refresh() {
        broken = FileHealth.broken(among: fileRecords, library: library)
            .sorted { $0.fileName < $1.fileName }
    }

    private func repair(with result: Result<URL, Error>) {
        defer { repairTarget = nil }

        guard case .success(let url) = result, let record = repairTarget else { return }

        record.relativePath = library.storedPath(for: url)
        record.fileName = url.lastPathComponent

        try? context.save()

        repaired += 1
        broken.removeAll { $0.persistentModelID == record.persistentModelID }
    }

    /// Detached from whichever side owns it before deleting, the way the files
    /// section does it — the record may belong to a lecture or to a paper.
    private func remove(_ record: LectureFile) {
        if let lecture = record.lecture {
            lecture.files.removeAll { $0.persistentModelID == record.persistentModelID }
        }
        if let exam = record.exam {
            exam.files.removeAll { $0.persistentModelID == record.persistentModelID }
        }

        broken.removeAll { $0.persistentModelID == record.persistentModelID }
        context.delete(record)
        try? context.save()
    }
}
