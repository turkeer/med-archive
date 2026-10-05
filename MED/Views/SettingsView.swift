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
            } header: {
                Text(L.pick("Dil", "Language"))
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
                    LabeledContent("Klasör") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.path(percentEncoded: false))
                                .lineLimit(2)
                                .truncationMode(.head)
                                .textSelection(.enabled)

                            if !library.exists {
                                Label("Bu klasör şu an diskte yok", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    Text("Seçilmedi")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Klasör seç…") {
                        isChoosingFolder = true
                    }

                    if library.url == nil && LibraryRoot.suggestionExists {
                        Button("Önerilen konumu kullan") {
                            library.set(LibraryRoot.suggestedURL)
                        }
                    }

                    if library.url != nil {
                        Button("Kaldır") {
                            library.set(nil)
                        }
                    }
                }
            } header: {
                Text("PDF kök klasörü")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Önerilen konum:\n\(LibraryRoot.suggestedURL.path(percentEncoded: false))")

                    Text("Kök klasörün altındaki dosyalar klasöre göre kaydedilir, böylece klasörü taşısan ya da yeniden adlandırsan da bağlar kopmaz. Uygulama dosyaları hiç kopyalamaz, taşımaz, silmez.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if let storeURL {
                    LabeledContent("Veritabanı") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(storeURL.path(percentEncoded: false))
                                .lineLimit(2)
                                .truncationMode(.head)
                                .textSelection(.enabled)

                            Button("Finder'da göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([storeURL])
                            }
                            .buttonStyle(.link)
                        }
                    }
                } else {
                    Text("Veritabanı açılamadı.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Yedek")
            } footer: {
                Text("Dosya menüsünden (⌘⇧E) arşivin tamamını okunabilir bir JSON dosyasına aktarabilirsin: ne var ne yok görmek ve veriyi başka bir yere taşımak için. Geri yükleme yapmıyor — asıl yedek yukarıdaki veritabanı dosyası, onu düzenli olarak kopyala.")
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
