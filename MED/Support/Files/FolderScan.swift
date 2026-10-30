import Foundation
import SwiftData

/// How sure the scan is about where a file belongs.
enum ScanConfidence {
    /// The date, the folder and the topic all agree, and nothing else on that
    /// day comes close.
    case certain

    /// Something matched, but not well enough to apply without a look.
    case weak

    /// Nothing on that day to attach it to — or no date in the name at all.
    case unmatched
}

/// One file the scan found, and what it proposes to do with it.
struct ScanFinding: Identifiable {
    let url: URL

    /// What would go into the record — relative to the library root when the
    /// file sits inside it. Also the identity of the row.
    let storedPath: String

    let name: ScanFileName

    /// The folder the file sits in, which is usually the course.
    let folderName: String

    let confidence: ScanConfidence

    /// What the scan proposes. `nil` only when nothing could be proposed.
    let lecture: Lecture?

    let score: Double

    /// The other topics taught that day, best guess first, for when the
    /// proposal is wrong.
    let alternatives: [Lecture]

    var id: String { storedPath }

    var fileName: String { url.lastPathComponent }

    /// An unmatched file can still become a session of its own, as long as its
    /// name said which day it was. Without a date there is nothing to create.
    var canCreateLecture: Bool {
        confidence == .unmatched && name.date != nil
    }
}

/// Matching the files on disk to the sessions in the archive.
///
/// Never runs by itself. A scan that fired on launch, or watched the folder,
/// would attach files while you were not looking — and the one thing worse
/// than linking slides by hand is finding them linked to the wrong lecture
/// and not knowing when it happened. So: a button, a list of proposals, and
/// nothing applied that was not ticked.
///
/// Nothing is ever copied, moved or renamed. A match writes one `LectureFile`
/// pointing at where the file already is.
enum FolderScan {
    /// Above this, a topic counts as corroborating the match.
    static let strongMatch = 0.6

    /// How far ahead of the runner-up the best match has to be. Two lectures
    /// on one day scoring 0.7 and 0.65 are a coin toss, not a certainty.
    static let decisiveGap = 0.15

    /// A guard against being pointed at a home folder by accident.
    static let fileLimit = 5000

    /// Every regular file under `root`, hidden ones skipped.
    static func files(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []

        for case let url as URL in walker {
            if found.count >= fileLimit { break }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            found.append(url)
        }

        return found.sorted { $0.path < $1.path }
    }

    /// What to propose for each file, skipping the ones already recorded.
    ///
    /// `attached` holds the stored paths of every existing file record, past
    /// papers included: a file already in the archive is not a finding, and a
    /// paper is not a lecture's slides.
    static func findings(
        in urls: [URL],
        lectures: [Lecture],
        courses: [Course],
        library: LibraryRoot,
        attached: Set<String>
    ) -> [ScanFinding] {
        // The archive is indexed by day once, rather than filtered per file.
        let calendar = Calendar.current
        var byDay: [Date: [Lecture]] = [:]

        for lecture in lectures {
            byDay[calendar.startOfDay(for: lecture.date), default: []].append(lecture)
        }

        return urls.compactMap { url in
            let storedPath = library.storedPath(for: url)
            guard !attached.contains(storedPath) else { return nil }

            return finding(
                url: url,
                storedPath: storedPath,
                byDay: byDay,
                courses: courses
            )
        }
    }

    private struct Ranked {
        let score: Double
        let lecture: Lecture
    }

    private static func finding(
        url: URL,
        storedPath: String,
        byDay: [Date: [Lecture]],
        courses: [Course]
    ) -> ScanFinding {
        let name = ScanNaming.read(url.lastPathComponent)
        let folderName = url.deletingLastPathComponent().lastPathComponent

        func unmatched() -> ScanFinding {
            ScanFinding(
                url: url,
                storedPath: storedPath,
                name: name,
                folderName: folderName,
                confidence: .unmatched,
                lecture: nil,
                score: 0,
                alternatives: []
            )
        }

        // The date is a hard filter, not a hint. Everything else about a file
        // can be wrong — the folder, the topic, the spelling — but a lecture
        // that happened on another day is not this file's lecture.
        guard let date = name.date, let sameDay = byDay[date], !sameDay.isEmpty else {
            return unmatched()
        }

        var candidates = sameDay
        var folderDisagrees = false

        if let course = course(named: folderName, among: courses) {
            let ofCourse = sameDay.filter {
                $0.course?.persistentModelID == course.persistentModelID
            }

            if ofCourse.isEmpty {
                // The folder names a course you have, and nothing from it was
                // taught that day. The evidence contradicts itself, so the
                // best this can come to is a suggestion.
                folderDisagrees = true
            } else {
                candidates = ofCourse
            }
        }

        // Scored per topic, not per record: the parts of one topic share their
        // files, so there is one decision to make and the first part holds it.
        let ranked = LectureGrouping.groups(of: candidates, sort: .oldestFirst)
            .map { Ranked(score: ScanNaming.similarity(name.topic, $0.first.displayTitle), lecture: $0.first) }
            .sorted { one, other in
                if one.score != other.score { return one.score > other.score }
                return (one.lecture.startMinutes ?? 0) < (other.lecture.startMinutes ?? 0)
            }

        guard let best = ranked.first else { return unmatched() }

        let runnerUp = ranked.count > 1 ? ranked[1].score : 0
        let certain: Bool

        if name.topic.isEmpty || folderDisagrees {
            // A name that is only a date says nothing about which of the day's
            // lessons it is, even when there is only one of them.
            certain = false
        } else if ranked.count == 1 {
            certain = best.score >= strongMatch
        } else {
            certain = best.score >= strongMatch && best.score - runnerUp >= decisiveGap
        }

        return ScanFinding(
            url: url,
            storedPath: storedPath,
            name: name,
            folderName: folderName,
            confidence: certain ? .certain : .weak,
            lecture: best.lecture,
            score: best.score,
            alternatives: ranked.dropFirst().map(\.lecture)
        )
    }

    /// The course a folder is named after.
    ///
    /// Containment either way, so that "Komite 1 - Anatomi" and "Anatomi
    /// (teorik)" both find Anatomi — but only from three letters up, or a
    /// one-letter folder would match everything.
    static func course(named folderName: String, among courses: [Course]) -> Course? {
        let folder = SearchText.fold(folderName)
        guard !folder.isEmpty else { return nil }

        return courses.first { course in
            let name = SearchText.fold(course.name)
            guard !name.isEmpty else { return false }
            if name == folder { return true }

            let shorter = min(name.count, folder.count)
            guard shorter >= 3 else { return false }

            return name.contains(folder) || folder.contains(name)
        }
    }
}
