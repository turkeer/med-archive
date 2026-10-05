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
            Label("Veritabanı açılamadı", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)

            Text("En olası sebep bir şema değişikliği: modele yeni bir alan eklendiğinde SwiftData eldeki veritabanını kendiliğinden göçürmeye çalışır ve bunu her zaman yapamaz.")

            GroupBox("Hata") {
                ScrollView {
                    Text(message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }

            GroupBox("Veritabanının yeri") {
                HStack {
                    Text(supportDirectory.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.head)

                    Spacer()

                    Button("Finder'da aç") {
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
                Text("Veritabanı silinmez, yedek klasöre taşınır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Veritabanını yedeğe taşı") {
                    isConfirmingReset = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
        .confirmationDialog(
            "Veritabanı yedeğe taşınsın mı?",
            isPresented: $isConfirmingReset
        ) {
            Button("Taşı", role: .destructive, action: moveStoreAside)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Uygulama boş bir veritabanıyla açılır. Eski veri silinmez, tarihli bir yedek klasörüne taşınır. Diskteki PDF'lere dokunulmaz.")
        }
    }

    /// Moves the store files aside rather than deleting them: a failed
    /// migration is recoverable, a deleted archive is not.
    private func moveStoreAside() {
        let manager = FileManager.default

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = supportDirectory
            .appending(path: "MED-yedek-\(stamp)", directoryHint: .isDirectory)

        do {
            let items = try manager.contentsOfDirectory(
                at: supportDirectory,
                includingPropertiesForKeys: nil
            )
            let storeFiles = items.filter { $0.lastPathComponent.hasPrefix("default.store") }

            guard !storeFiles.isEmpty else {
                status = "Burada taşınacak bir veritabanı bulunamadı. Sorun şema göçü olmayabilir — Xcode konsolundaki hatayı paylaş."
                return
            }

            try manager.createDirectory(at: backup, withIntermediateDirectories: true)
            for file in storeFiles {
                try manager.moveItem(at: file, to: backup.appending(path: file.lastPathComponent))
            }

            status = "\(storeFiles.count) dosya taşındı:\n\(backup.path(percentEncoded: false))\n\nUygulamayı kapat ve yeniden çalıştır."
        } catch {
            status = "Taşıma başarısız oldu: \(error)"
        }
    }
}
