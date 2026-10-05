import SwiftUI
import UniformTypeIdentifiers

/// Settings, reachable with ⌘, — just the library root for now.
struct SettingsView: View {
    @Environment(LibraryRoot.self) private var library

    @State private var isChoosingFolder = false

    var body: some View {
        Form {
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
        .frame(width: 540, height: 320)
    }
}
