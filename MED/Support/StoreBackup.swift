import Foundation
import SwiftData

/// A JSON copy of the whole archive, written on launch.
///
/// The export in the File menu is something you decide to do; this one is not
/// meant to be thought about. The archive is small — a term of lectures is
/// tens of kilobytes — so a copy per launch costs nothing, and it is the
/// difference between "the database is empty" and "the database is empty, and
/// here is how it looked yesterday".
///
/// Written to `~/Library/Application Support/MED/Backups`, beside the store.
enum StoreBackup {
    static var directory: URL {
        StoreLocation.directory.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// Roughly two weeks of launches. These files are tiny; the limit is about
    /// keeping the folder readable, not about space.
    private static let keep = 14

    /// One file per day, rewritten on each launch of that day, so the newest
    /// backup is never more than a session old.
    static func write(from context: ModelContext) {
        do {
            let snapshot = ArchiveExport.snapshot(from: context)

            // Never let an empty archive overwrite a day's good backup. An
            // empty store is the one case where the backups matter most, and
            // it is exactly the case where the snapshot has nothing in it.
            guard !snapshot.lectures.isEmpty else { return }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ArchiveExport.json(snapshot).write(to: directory.appending(path: fileName()), options: .atomic)
            prune()
        } catch {
            // A backup that cannot be written is not a reason to refuse to
            // start. The console line is enough to find out why.
            print("MED: yedek yazılamadı — \(error)")
        }
    }

    /// The newest backup on disk, for the failure screen to point at.
    static var newest: URL? { files().first }

    private static func fileName(on day: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return "MED-\(formatter.string(from: day)).json"
    }

    /// Newest first. The names sort by date on their own, which is the point
    /// of naming them that way.
    private static func files() -> [URL] {
        let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        return (items ?? [])
            .filter { $0.lastPathComponent.hasPrefix("MED-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func prune() {
        for file in files().dropFirst(keep) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
