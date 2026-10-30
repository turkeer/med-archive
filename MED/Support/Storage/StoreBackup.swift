import AppKit
import Foundation
import SwiftData

/// A JSON copy of the whole archive, kept up to date while the app is open.
///
/// The export in the File menu is something you decide to do; this one is not
/// meant to be thought about. The archive is small — a term of lectures is
/// tens of kilobytes — so writing it again costs nothing, and it is the
/// difference between "the database is empty" and "the database is empty, and
/// here is how it looked an hour ago".
///
/// Written to `~/Library/Application Support/MED/Backups`, beside the store.
///
/// On the main actor for the mutable `lastWrite` below, and because every
/// caller is a view or the app itself.
@MainActor
enum StoreBackup {
    static var directory: URL {
        StoreLocation.directory.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// Roughly two weeks. These files are tiny; the limit is about keeping the
    /// folder readable, not about space.
    private static let keep = 14

    /// How often a write is worth doing while the app is open.
    ///
    /// The first version of this only wrote on launch, which missed the case
    /// that matters most: this app is left open. Over a fortnight of being
    /// open, the archive here went from 78 lectures to 154 while the newest
    /// backup stayed on the first day — a backup that stops tracking the
    /// thing it backs up is not one.
    private static let interval: TimeInterval = 60 * 60

    /// Switching away from the app and straight back should not rewrite the
    /// file twice. A minute is enough to stop that without letting the copy
    /// drift behind the archive.
    private static let minimumGap: TimeInterval = 60

    private static var lastWrite: Date?

    /// Writes one now, then once an hour for as long as the caller lives.
    ///
    /// Cancelling the task — the window going away — ends the loop.
    static func keepWriting(from context: ModelContext) async {
        while !Task.isCancelled {
            write(from: context)
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }

    /// Writes whenever the app stops being the one in front, which is when
    /// you have just finished putting something in.
    ///
    /// `scenePhase` looked like the way to do this and is not: on macOS a
    /// window sitting behind another app is still `.active`, so the phase
    /// never changes and nothing was ever written. Hiding the app did not
    /// change it either. AppKit's own notification does arrive.
    static func writeOnLeaving(from context: ModelContext) async {
        let left = NotificationCenter.default.notifications(named: NSApplication.didResignActiveNotification)

        for await _ in left {
            write(from: context)
        }
    }

    /// One file per day, rewritten as the day goes on, so the newest backup
    /// is at most an hour behind the archive.
    static func write(from context: ModelContext) {
        guard isDue else { return }

        do {
            let snapshot = ArchiveExport.snapshot(from: context)

            // Never let an empty archive overwrite a day's good backup. An
            // empty store is the one case where the backups matter most, and
            // it is exactly the case where the snapshot has nothing in it.
            guard !snapshot.lectures.isEmpty else { return }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ArchiveExport.json(snapshot).write(to: directory.appending(path: fileName()), options: .atomic)
            lastWrite = Date()
            prune()
        } catch {
            // A backup that cannot be written is not a reason to refuse to
            // start. The console line is enough to find out why.
            print("MED: yedek yazılamadı — \(error)")
        }
    }

    /// The newest backup on disk, for the failure screen to point at.
    static var newest: URL? { files().first }

    private static var isDue: Bool {
        guard let lastWrite else { return true }
        return Date().timeIntervalSince(lastWrite) >= minimumGap
    }

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
