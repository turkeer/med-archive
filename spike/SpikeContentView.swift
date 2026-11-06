import SwiftUI
import UniformTypeIdentifiers

/// Spike arayüzü: PDF içe al (konteynere), listeden birini aç, kalemle yaz.
///
/// İki kanıtı tek ekranda birleştirir:
/// 1. "PDF içe al" → `ContainerStore` dış dosyayı konteynere kopyalar.
/// 2. Bir satıra dokun → `PencilPDFReader` onu Pencil'la açar.
struct SpikeContentView: View {
    @State private var store = ContainerStore()
    @State private var importing = false
    @State private var opened: ContainerStore.ImportedFile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        importing = true
                    } label: {
                        Label("PDF içe al (konteynere kopyala)", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        store.makeSamplePDF(pages: 200)
                    } label: {
                        Label("200 sayfalık örnek PDF üret", systemImage: "doc.badge.plus")
                    }
                } footer: {
                    Text("Seçtiğin PDF uygulamanın Documents/Library klasörüne kopyalanır. "
                        + "Açarken security-scoped bookmark kullanılmaz.")
                }

                Section("İçe alınanlar (\(store.files.count))") {
                    if store.files.isEmpty {
                        Text("Henüz dosya yok").foregroundStyle(.secondary)
                    }
                    ForEach(store.files) { file in
                        Button {
                            opened = file
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                Text(file.relativePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MED iPad Spike")
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls { store.importFile(from: url) }
                }
            }
            .fullScreenCover(item: $opened) { file in
                ReaderScreen(file: file) { opened = nil }
            }
        }
    }
}

/// Okuyucuyu tam ekran, bir kapatma çubuğuyla gösterir.
private struct ReaderScreen: View {
    let file: ContainerStore.ImportedFile
    let onClose: () -> Void

    @State private var status = "…"
    @StateObject private var controller = ReaderController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Kapat", action: onClose)
                Spacer()
                Button { controller.prev() } label: { Image(systemName: "chevron.left") }
                Button { controller.next() } label: { Image(systemName: "chevron.right") }
                Spacer()
                Text(file.name).font(.caption).lineLimit(1)
            }
            .padding()

            Text(status)
                .font(.caption)
                .foregroundStyle(status.hasPrefix("PDF YÜKLENEMEDİ") ? .red : .secondary)
                .padding(.bottom, 6)

            Divider()

            PencilPDFReader(url: file.url, controller: controller) { status = $0 }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
