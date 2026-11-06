import Foundation
import UIKit

/// Kanıt #1: iOS'ta dosyaları uygulamanın **kendi konteynerine** alıp
/// security-scoped bookmark olmadan açabiliyor muyuz?
///
/// MED'in Mac modeli: sandbox'sız, dış klasöre referans, `relativePath`.
/// iPad modeli (bu spike): dosyayı `Documents/` altına **kopyala**, sonra düz
/// yolla eriş. Bookmark, `startAccessingSecurityScopedResource` kalıcılığı —
/// hiçbiri yok.
///
/// Tek yer scope gerektiriyor: içe alma anında dış kaynağı **okumak** için.
/// Bu geçici ve tek seferlik — kopyaladıktan sonra bir daha asla gerekmiyor.
/// MED'in Mac'te sildiği "kalıcı bookmark" derdiyle karıştırılmamalı.
@Observable
final class ContainerStore {

    /// `~/.../Documents/Library` — içe alınan PDF'lerin yaşadığı yer.
    static var libraryURL: URL {
        let docs = URL.documentsDirectory
        return docs.appending(path: "Library", directoryHint: .isDirectory)
    }

    private(set) var files: [ImportedFile] = []

    struct ImportedFile: Identifiable, Hashable {
        /// **Gerçek on-disk URL** — doğrudan `contentsOfDirectory`'den gelir,
        /// yeniden kurulmaz. Böylece Türkçe karakter/boşluk normalizasyonu
        /// (NFC/NFD) yüzünden yol kaymaz. Bookmark yok, scope yok.
        let url: URL

        /// Konteyner köküne (`Documents/`) göreli yol — MED'in `relativePath`'inin
        /// birebir iPad karşılığı. Yalnızca gösterim için.
        let relativePath: String

        var id: String { url.path(percentEncoded: false) }
        var name: String { url.lastPathComponent }
    }

    init() {
        try? FileManager.default.createDirectory(
            at: Self.libraryURL, withIntermediateDirectories: true
        )
        reload()
    }

    /// Konteynerdeki PDF'leri tara.
    func reload() {
        let root = URL.documentsDirectory
        let found = (try? FileManager.default.contentsOfDirectory(
            at: Self.libraryURL,
            includingPropertiesForKeys: nil
        )) ?? []

        files = found
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { url in
                let full = url.standardizedFileURL.path(percentEncoded: false)
                let base = root.standardizedFileURL.path(percentEncoded: false) + "/"
                let rel = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : url.lastPathComponent
                return ImportedFile(url: url, relativePath: rel)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Seçilen dış `source`'u konteynere kopyala.
    ///
    /// `source` security-scoped (fileImporter'dan geliyor): okumak için bir
    /// kerelik scope açılıyor, kopya bitince kapanıyor. Hedef konteyner-içi,
    /// ona scope gerekmiyor.
    @discardableResult
    func importFile(from source: URL) -> ImportedFile? {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let destination = uniqueDestination(for: source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            print("Spike: içe alma hatası — \(error)")
            return nil
        }

        reload()
        return files.first { $0.name == destination.lastPathComponent }
    }

    /// Simülatör testi için: Files seçiciyle uğraşmadan, konteynere büyük bir
    /// çok-sayfalı PDF üret. Akıcılık/kalıcılık testinin "büyük deste" ayağını
    /// bu besler. (Gerçek içe alma yolu `importFile` ile ayrıca duruyor.)
    @discardableResult
    func makeSamplePDF(pages: Int = 200) -> ImportedFile? {
        let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let destination = uniqueDestination(for: "Örnek \(pages) sayfa.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)

        do {
            try renderer.writePDF(to: destination) { ctx in
                for i in 1...pages {
                    ctx.beginPage()
                    let title = "Sayfa \(i) / \(pages)"
                    title.draw(at: CGPoint(x: 48, y: 60), withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 34)
                    ])
                    // Biraz gövde metni — seçme/kaydırma için gerçekçi yoğunluk.
                    let body = (1...24).map { "  • Örnek satır \($0) — anatomi/fizyoloji yer tutucu metin." }
                        .joined(separator: "\n")
                    body.draw(in: CGRect(x: 48, y: 120, width: 516, height: 620), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 15)
                    ])
                }
            }
        } catch {
            print("Spike: örnek PDF üretilemedi — \(error)")
            return nil
        }

        reload()
        return files.first { $0.name == destination.lastPathComponent }
    }

    /// Aynı ad varsa " 2", " 3" ekleyerek çakışmayı önle.
    private func uniqueDestination(for fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = Self.libraryURL.appending(path: fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = Self.libraryURL.appending(path: name)
            n += 1
        }
        return candidate
    }
}
