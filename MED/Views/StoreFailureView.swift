import AppKit
import SwiftUI

/// Shown when the database cannot be opened.
///
/// This replaces a `fatalError`, which killed the app before any window
/// appeared: the Dock icon showed up, nothing opened, and the reason was
/// buried in the console. A failure that explains itself is worth a window.
struct StoreFailureView: View {
    let message: String

    @State private var isConfirmingReset = false
    @State private var status: String?

    private var supportDirectory: URL {
        URL.applicationSupportDirectory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L.pick("Veritabanı açılamadı", "The database could not be opened"), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)

            Text(L.pick(
                "En olası sebep bir şema değişikliği: modele yeni bir alan eklendiğinde SwiftData eldeki veritabanını kendiliğinden göçürmeye çalışır ve bunu her zaman yapamaz.",
                "The likeliest cause is a schema change: when a new field is added to the model, SwiftData tries to migrate the existing database on its own, and it cannot always do it."
            ))

            GroupBox(L.pick("Hata", "Error")) {
                ScrollView {
                    Text(message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }

            GroupBox(L.pick("Veritabanının yeri", "Where the database is")) {
                HStack {
                    Text(supportDirectory.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.head)

                    Spacer()

                    Button(L.pick("Finder'da aç", "Open in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([supportDirectory])
                    }
                }
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            HStack {
                Text(L.pick("Veritabanı silinmez, yedek klasöre taşınır.", "The database is not deleted, it is moved to a backup folder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L.pick("Veritabanını yedeğe taşı", "Move the database aside")) {
                    isConfirmingReset = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
        .confirmationDialog(
            L.pick("Veritabanı yedeğe taşınsın mı?", "Move the database aside?"),
            isPresented: $isConfirmingReset
        ) {
            Button(L.pick("Taşı", "Move"), role: .destructive, action: moveStoreAside)
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(L.pick(
                "Uygulama boş bir veritabanıyla açılır. Eski veri silinmez, tarihli bir yedek klasörüne taşınır. Diskteki PDF'lere dokunulmaz.",
                "The app opens with an empty database. The old data is not deleted, it is moved into a dated backup folder. The PDFs on disk are untouched."
            ))
        }
    }

    /// Moves the store files aside rather than deleting them: a failed
    /// migration is recoverable, a deleted archive is not.
    private func moveStoreAside() {
        let manager = FileManager.default

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = supportDirectory
            .appending(path: L.pick("MED-yedek-", "MED-backup-") + stamp, directoryHint: .isDirectory)

        do {
            let items = try manager.contentsOfDirectory(
                at: supportDirectory,
                includingPropertiesForKeys: nil
            )
            let storeFiles = items.filter { $0.lastPathComponent.hasPrefix("default.store") }

            guard !storeFiles.isEmpty else {
                status = L.pick(
                    "Burada taşınacak bir veritabanı bulunamadı. Sorun şema göçü olmayabilir — Xcode konsolundaki hatayı paylaş.",
                    "No database was found here to move. The problem may not be a schema migration — share the error from the Xcode console."
                )
                return
            }

            try manager.createDirectory(at: backup, withIntermediateDirectories: true)
            for file in storeFiles {
                try manager.moveItem(at: file, to: backup.appending(path: file.lastPathComponent))
            }

            let moved = L.pick(
                "\(storeFiles.count) dosya taşındı:",
                "\(storeFiles.count) files moved:"
            )
            let next = L.pick(
                "Uygulamayı kapat ve yeniden çalıştır.",
                "Quit the app and run it again."
            )
            status = moved + "\n\(backup.path(percentEncoded: false))\n\n" + next
        } catch {
            status = L.pick("Taşıma başarısız oldu: ", "The move failed: ") + "\(error)"
        }
    }
}
