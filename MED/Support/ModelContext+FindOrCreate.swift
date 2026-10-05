import Foundation
import SwiftData

/// Turning a typed name into a record, without letting the same thing pile up
/// under two spellings. A name that folds to an existing one reuses that
/// record; anything else becomes a new one.
extension ModelContext {
    func findOrCreateCourse(named rawName: String) -> Course? {
        findOrCreate(rawName, name: \Course.name) { Course(name: $0) }
    }

    func findOrCreateInstructor(named rawName: String) -> Instructor? {
        findOrCreate(rawName, name: \Instructor.name) { Instructor(name: $0) }
    }

    func findOrCreateCommittee(named rawName: String) -> Committee? {
        findOrCreate(rawName, name: \Committee.name) { Committee(name: $0) }
    }

    func findOrCreateTag(named rawName: String) -> Tag? {
        findOrCreate(rawName, name: \Tag.name) { Tag(name: $0) }
    }

    private func findOrCreate<T: PersistentModel>(
        _ rawName: String,
        name keyPath: KeyPath<T, String>,
        make: (String) -> T
    ) -> T? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // The record counts are small enough that fetching all of them and
        // folding in memory is simpler, and more forgiving, than a predicate.
        let existing = (try? fetch(FetchDescriptor<T>())) ?? []
        if let match = existing.first(where: { SearchText.sameName($0[keyPath: keyPath], trimmed) }) {
            return match
        }

        let created = make(trimmed)
        insert(created)
        return created
    }
}
