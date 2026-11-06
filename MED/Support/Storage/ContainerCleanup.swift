#if os(iOS)
import Foundation
import SwiftData

/// iOS'ta dosyalar uygulamanın konteynerine **kopyalanıyor** (macOS'taki
/// referans modelinin tersine). Dolayısıyla bir kayıt (ders dosyası ya da
/// geçmiş sınav dosyası) silinince, konteynerdeki kopyası öksüz kalır ve
/// fihrist/sözlük onu görmeye devam eder. Bu, hiçbir kayda bağlı olmayan
/// dosyaları siler.
///
/// macOS'ta çağrılmaz: orada dosyanın sahibi kullanıcı, uygulama değil — bir
/// kaydı silmek kullanıcının dosyasını asla silmez ("hiçbir şey kopyalanmaz").
enum ContainerCleanup {
    /// Konteyner kök klasöründe (Library) hiçbir `LectureFile` kaydının
    /// işaret etmediği dosyaları siler. Açılışta, fihristlemeden önce çağrılır.
    static func removeOrphans(context: ModelContext, library: LibraryRoot) {
        guard let root = library.url else { return }

        // GÜVENLİK: fetch başarısız olursa HİÇBİR ŞEY silme. Aksi halde boş bir
        // referans kümesiyle kullanıcının tüm dosyaları silinir (veri kaybı).
        // Geçmiş sınav dosyaları da ordinary LectureFile kayıtları olduğu için
        // tek fetch ikisini de kapsar.
        guard let records = try? context.fetch(FetchDescriptor<LectureFile>()) else { return }
        let referenced = Set(records.map(\.relativePath))

        let onDisk = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        for fileURL in onDisk {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }

            let rel = library.storedPath(for: fileURL)
            if !referenced.contains(rel) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
#endif
