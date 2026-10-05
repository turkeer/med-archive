import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings, reachable with ⌘, — the library root and where the data lives.
struct SettingsView: View {
    /// Where SwiftData keeps the store. Shown rather than hidden, because
    /// this one file *is* the archive: the JSON export is for reading, and
    /// what gets copied to iCloud or Time Machine is this.
    var storeURL: URL?

    @Environment(LibraryRoot.self) private var library

    @State private var isChoosingFolder = false

    /// Reads and writes the shared object directly. A `@State` copy would own
    /// a second one, and the rest of the app would never hear about the
    /// change.
    private var languageBinding: Binding<AppLanguageChoice> {
        Binding(
            get: { AppLanguage.shared.choice },
            set: { AppLanguage.shared.choice = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L.pick("Dil", "Language"), selection: languageBinding) {
                    ForEach(AppLanguageChoice.allCases) { choice in
                        Text(choice.endonym).tag(choice)
                    }
                }
            } footer: {
                Text(L.pick(
                    "Hemen değişir, uygulamayı kapatmak gerekmez. Ders adları, konular ve notlar senin yazdığın gibi kalır — çevrilen yalnızca arayüz.",
                    "Takes effect at once, with no need to quit. Course names, topics and notes stay exactly as you typed them — only the interface is translated."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if let url = library.url {
                    LabeledContent(L.pick("Klasör", "Folder")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.path(percentEncoded: false))
                                .lineLimit(2)
                                .truncationMode(.head)
                                .textSelection(.enabled)

                            if !library.exists {
                                Label(L.pick("Bu klasör şu an diskte yok", "This folder is not on disk right now"), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    Text(L.pick("Seçilmedi", "Not chosen"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(L.chooseFolder) {
                        isChoosingFolder = true
                    }

                    if library.url == nil && LibraryRoot.suggestionExists {
                        Button(L.pick("Önerilen konumu kullan", "Use the suggested location")) {
                            library.set(LibraryRoot.suggestedURL)
                        }
                    }

                    if library.url != nil {
                        Button(L.remove) {
                            library.set(nil)
                        }
                    }
                }
            } header: {
                Text(L.pick("PDF kök klasörü", "PDF root folder"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.pick("Önerilen konum:", "Suggested location:") + "\n\(LibraryRoot.suggestedURL.path(percentEncoded: false))")

                    Text(L.pick(
                        "Kök klasörün altındaki dosyalar klasöre göre kaydedilir, böylece klasörü taşısan ya da yeniden adlandırsan da bağlar kopmaz. Uygulama dosyaları hiç kopyalamaz, taşımaz, silmez.",
                        "Files under the root folder are stored relative to it, so moving or renaming the folder does not break the links. The app never copies, moves or deletes a file."
                    ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if let storeURL {
                    LabeledContent(L.pick("Veritabanı", "Database")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(storeURL.path(percentEncoded: false))
                                .lineLimit(2)
                                .truncationMode(.head)
                                .textSelection(.enabled)

                            Button(L.showInFinder) {
                                NSWorkspace.shared.activateFileViewerSelecting([storeURL])
                            }
                            .buttonStyle(.link)
                        }
                    }
                } else {
                    Text(L.pick("Veritabanı açılamadı.", "The database could not be opened."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L.pick("Yedek", "Backup"))
            } footer: {
                Text(L.pick(
                    "Dosya menüsünden (⌘⇧E) arşivin tamamını okunabilir bir JSON dosyasına aktarabilirsin: ne var ne yok görmek ve veriyi başka bir yere taşımak için. Geri yükleme yapmıyor — asıl yedek yukarıdaki veritabanı dosyası, onu düzenli olarak kopyala.",
                    "The File menu (⌘⇧E) exports the whole archive as a readable JSON file: for checking what is there and for carrying the data elsewhere. It does not restore — the real backup is the database file above, so copy that regularly."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [UTType.folder]
        ) { result in
            if case .success(let url) = result {
                library.set(url)
            }
        }
        .frame(width: 560, height: 540)
    }
}
