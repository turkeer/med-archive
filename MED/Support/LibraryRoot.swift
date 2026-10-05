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
        let path = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        if !path.isEmpty {
            url = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    /// The folder the design suggests, whether or not it exists yet.
    static var suggestedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/MED", directoryHint: .isDirectory)
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
