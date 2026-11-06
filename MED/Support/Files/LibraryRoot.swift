import Foundation
import Observation

/// Where the PDF library sits on disk.
///
/// A plain path, not a security-scoped bookmark. The app is deliberately not
/// sandboxed — it is never going to the App Store — so a path is all that is
/// needed, and the whole bookmark layer disappears: no stale bookmarks, no
/// re-acquiring access on every launch, no `startAccessingSecurityScopedResource`.
@Observable
final class LibraryRoot {
    private static let defaultsKey = "MEDLibraryRootPath"

    private(set) var url: URL?

    init() {
        #if os(iOS)
        // iOS: kök her zaman konteynerin Library klasörü. Konteyner yolu
        // kurulumlar arası değişebildiği için mutlak yolu saklamıyoruz; her
        // açılışta yeniden hesaplanıyor. Dosyalar bu klasöre içe alınır.
        let container = Self.suggestedURL
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        url = container
        #else
        let path = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        if !path.isEmpty {
            url = URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
    }

    /// The folder the design suggests, whether or not it exists yet.
    static var suggestedURL: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/MED", directoryHint: .isDirectory)
        #else
        // iOS: sandbox gereği dosyalar uygulamanın kendi konteynerinde yaşar.
        URL.documentsDirectory.appending(path: "Library", directoryHint: .isDirectory)
        #endif
    }

    static var suggestionExists: Bool {
        exists(at: suggestedURL)
    }

    var exists: Bool {
        guard let url else { return false }
        return Self.exists(at: url)
    }

    static func exists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return found && isDirectory.boolValue
    }

    func set(_ newURL: URL?) {
        url = newURL

        if let newURL {
            UserDefaults.standard.set(newURL.path(percentEncoded: false), forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }

    /// Seçilen bir dosyayı kayda hazırlar.
    ///
    /// macOS: dosya olduğu yerde kalır, referans edilir (source geri döner).
    /// iOS: sandbox gereği dış dosyaya kalıcı erişim yok — konteynerin
    /// Library'sine bir kopya alınır ve o kopyanın URL'i döner.
    func prepareForAttach(_ source: URL) -> URL? {
        #if os(iOS)
        return copyIntoContainer(source)
        #else
        return source
        #endif
    }

    #if os(iOS)
    /// Dış (security-scoped) dosyayı konteynere kopyalar. Scope yalnızca
    /// kopyalama anında; kalıcı bookmark yok.
    private func copyIntoContainer(_ source: URL) -> URL? {
        guard let root = url else { return nil }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = Self.uniqueDestination(in: root, name: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            print("LibraryRoot: içe alma hatası — \(error)")
            return nil
        }
    }

    /// Aynı ad varsa " 2", " 3" ekleyerek çakışmayı (ve üzerine yazmayı) önler.
    private static func uniqueDestination(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appending(path: newName)
            n += 1
        }
        return candidate
    }
    #endif

    /// What to store for a file: a path relative to the root when the file sits
    /// inside it, which survives the root folder being moved or renamed, and an
    /// absolute path when it was picked from somewhere else.
    func storedPath(for fileURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        guard let url else { return filePath }

        let rootPath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard filePath.hasPrefix(prefix) else { return filePath }
        return String(filePath.dropFirst(prefix.count))
    }
}
