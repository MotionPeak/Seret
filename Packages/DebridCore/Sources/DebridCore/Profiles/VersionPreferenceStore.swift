#if canImport(SwiftData)
import Foundation
import SwiftData

/// The user's chosen default version per title. `@ModelActor` isolates its `ModelContext`, so it
/// is safe from any task.
///
/// Method names avoid `preferred`/`choose`/`clear` on purpose: the `VersionPreferring` seam in
/// DebridUI declares non-throwing async versions of those, and same-named throwing overloads make
/// the conformance ambiguous.
@ModelActor
public actor VersionPreferenceStore {
    /// The chosen source key, or nil when the ranker should decide.
    public func preferredSourceKey(forContentKey key: String) throws -> String? {
        try rows(forContentKey: key).first?.sourceKey
    }

    /// Record a choice, collapsing any duplicate rows CloudKit may have produced.
    public func setChoice(contentKey: String, sourceKey: String, at: Date = Date()) throws {
        let existing = try rows(forContentKey: contentKey)
        for extra in existing.dropFirst() { modelContext.delete(extra) }
        let row = existing.first ?? {
            let r = VersionPreference(); modelContext.insert(r); return r
        }()
        row.contentKey = contentKey
        row.sourceKey = sourceKey
        row.chosenAt = at
        try modelContext.save()
    }

    /// Fall back to the quality ranker for this title.
    public func clearChoice(contentKey: String) throws {
        for row in try rows(forContentKey: contentKey) { modelContext.delete(row) }
        try modelContext.save()
    }

    public func count() throws -> Int {
        try modelContext.fetch(FetchDescriptor<VersionPreference>()).count
    }

    /// Test hook: write a row without collapsing duplicates, to simulate a CloudKit merge.
    func insertRawForTest(contentKey: String, sourceKey: String, at: Date) throws {
        modelContext.insert(VersionPreference(contentKey: contentKey, sourceKey: sourceKey,
                                              chosenAt: at))
        try modelContext.save()
    }

    /// Newest first — CloudKit cannot enforce uniqueness, so last write wins.
    private func rows(forContentKey key: String) throws -> [VersionPreference] {
        try modelContext.fetch(FetchDescriptor<VersionPreference>(
            predicate: #Predicate { $0.contentKey == key },
            sortBy: [SortDescriptor(\.chosenAt, order: .reverse)]))
    }
}
#endif
