import Foundation
import SwiftData

/// Filling in what the data already implies, so the same answer is not typed
/// hundreds of times.
extension ModelContext {
    /// The one committee whose date range covers `day`.
    ///
    /// Returns `nil` when none covers it, and also when several do: an
    /// overlapping range is ambiguous, and leaving the field empty is better
    /// than picking one of two silently.
    func committee(covering day: Date) -> Committee? {
        let all = (try? fetch(FetchDescriptor<Committee>())) ?? []
        let covering = all.filter { $0.covers(day) }
        return covering.count == 1 ? covering.first : nil
    }

    /// Lectures inside a committee's range that have no committee set.
    func lecturesAwaiting(_ committee: Committee) -> [Lecture] {
        let all = (try? fetch(FetchDescriptor<Lecture>())) ?? []
        return all.filter { $0.committee == nil && committee.covers($0.date) }
    }
}
