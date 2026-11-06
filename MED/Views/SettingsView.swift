import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Settings, reachable with ⌘, — the library root and where the data lives.
struct SettingsView: View {
    /// Where SwiftData keeps the store. Shown rather than hidden, because
    /// this one file *is* the archive: the JSON export is for reading, and
    /// what gets copied to iCloud or Time Machine is this.
    var storeURL: URL?

    @Environment(LibraryRoot.self) private var library
    @Environment(SlideIndex.self) private var slideIndex
    @Environment(ReferenceLibrary.self) private var reference

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

                            #if os(macOS)
                            Button(L.showInFinder) {
                                NSWorkspace.shared.activateFileViewerSelecting([storeURL])
                            }
                            .linkButtonStyle()
                            #endif
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

            Section {
                LabeledContent(L.pick("Slayt fihristi", "Slide index")) {
                    VStack(alignment: .leading, spacing: 2) {
                        if slideIndex.fileCount == 0, slideIndex.isWorking {
                            Text(L.pick("okunuyor…", "reading…"))
                                .foregroundStyle(.secondary)
                        } else if slideIndex.fileCount == 0 {
                            Text(L.pick("henüz kurulmadı", "not built yet"))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L.pick(
                                "\(slideIndex.fileCount) dosya · \(slideIndex.pageCount) sayfa",
                                "\(slideIndex.fileCount) files · \(slideIndex.pageCount) pages"
                            ))

                            if slideIndex.isWorking {
                                Text(L.pick("resimli sayfalar okunuyor…", "reading the image pages…"))
                                    .foregroundStyle(.secondary)
                            }

                            if slideIndex.ocrPageCount > 0 {
                                Text(L.pick(
                                    "\(slideIndex.ocrPageCount) sayfa görüntüden okundu",
                                    "\(slideIndex.ocrPageCount) pages read from the image"
                                ))
                                    .foregroundStyle(.secondary)
                            }

                            if slideIndex.unreadablePageCount > 0 {
                                // Said out loud rather than left as a silent
                                // hole: a search that misses these reads as
                                // "the word is not in your slides".
                                Text(L.pick(
                                    "\(slideIndex.unreadablePageCount) sayfada okunacak metin yok",
                                    "\(slideIndex.unreadablePageCount) pages have no readable text"
                                ))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text(L.pick("Arama", "Search"))
            } footer: {
                Text(L.pick(
                    "Kök klasördeki bütün PDF'lerin metni okunur, böylece arama slaytların içinde de bulur. Metni olmayan sayfalar — taranmış slaytlar, yazısı resmin içinde olan diyagramlar — görüntüden okunur. Fihrist veritabanının yanında ayrı bir dosyada tutulur; silinse bir sonraki açılışta yeniden kurulur.",
                    "The text of every PDF under the root folder is read, so searching reaches inside the slides. Pages with no text of their own — scanned slides, diagrams whose labels live in the picture — are read from the image instead. The index is kept in its own file beside the database; delete it and it is rebuilt on the next launch."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                switch reference.phase {
                case .absent:
                    Button(L.pick("Atlası indir", "Download the atlas")) {
                        reference.startDownload()
                    }

                case .downloading(let fraction):
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: fraction)
                        HStack {
                            Text("\(Int(fraction * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L.pick("Duraklat", "Pause")) { reference.pauseDownload() }
                        }
                    }

                case .indexing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.pick("okunuyor…", "reading…")).foregroundStyle(.secondary)
                    }

                case .ready:
                    LabeledContent(L.pick("Atlas", "Atlas")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.pick(
                                "Hazır · \(reference.pageCount) sayfa",
                                "Ready · \(reference.pageCount) pages"
                            ))
                            Button(L.remove) { reference.removeDownload() }
                                .linkButtonStyle()
                        }
                    }

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 6) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button(L.pick("Tekrar dene", "Try again")) { reference.startDownload() }
                    }
                }
            } header: {
                Text(L.pick("Atlas (ek kaynak)", "Atlas (reference)"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.pick(
                        "OpenStax Anatomy and Physiology 2e, slaytlarınla çalışırken ek kaynak olarak kullanılır — kendi arşivine karışmaz, bir derse bağlanmaz. Yaklaşık 476 MB; OpenStax'ten bir kez indirilir, metni bu bilgisayarda okunur ve sonrası çevrimdışı çalışır.",
                        "OpenStax Anatomy and Physiology 2e, used as a reference while you study your slides — it stays out of your own archive and is never attached to a lecture. About 476 MB; downloaded once from OpenStax, its text is read on this computer, and it works offline afterwards."
                    ))
                    Text(ReferenceLibrary.attribution)
                    Link(L.pick("Kaynak sayfası", "Source page"), destination: ReferenceLibrary.sourcePageURL)
                }
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
        .frame(width: 560, height: 640)
    }
}
