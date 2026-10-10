import Foundation

/// Where the database lives.
///
/// This used to be left to SwiftData's default, which was a mistake with
/// teeth. The app is not sandboxed, so `URL.applicationSupportDirectory` is
/// the user-wide `~/Library/Application Support`, and the default store name
/// there is `default.store` — a name nobody owns. On 8 October 2026 another
/// unsandboxed Core Data client, `com.apple.icloudmailagent`, opened that same
/// file and migrated it to its own schema; every lecture in it was dropped,
/// and the next launch of MED migrated the leftovers back and found an empty
/// archive. Both writers were recorded in the store's own history table, which
/// is the only reason it could be worked out at all.
///
/// So the path is explicit now, and under a folder with this app's name on it.
enum StoreLocation {
    /// `~/Library/Application Support/MED`
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "MED", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/MED/MED.store`
    static var storeURL: URL {
        directory.appending(path: storeName)
    }

    static let storeName = "MED.store"

    /// The store, plus the two side files SQLite keeps beside it.
    static let companionSuffixes = ["", "-wal", "-shm"]

    /// The shared path used before this type existed. Kept only so an archive
    /// written back then can be brought along once.
    private static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Creates the folder and adopts a pre-move archive. Call before opening
    /// the container.
    ///
    /// Failures are thrown rather than swallowed: carrying on would open a
    /// second, empty archive somewhere else, which is how data gets lost
    /// quietly.
    static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try adoptLegacyStore()
    }

    /// Moves `default.store` into place, once, if there is nothing here yet.
    private static func adoptLegacyStore() throws {
        let manager = FileManager.default
        let legacyPath = legacyStoreURL.path(percentEncoded: false)

        // Nothing to do once this folder has a store of its own, and nothing
        // to do if the old path was never used.
        guard !manager.fileExists(atPath: storeURL.path(percentEncoded: false)),
              manager.fileExists(atPath: legacyPath)
        else { return }

        for suffix in companionSuffixes {
            let from = URL(filePath: legacyPath + suffix)
            guard manager.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            try manager.moveItem(at: from, to: URL(filePath: storeURL.path(percentEncoded: false) + suffix))
        }
    }
}
