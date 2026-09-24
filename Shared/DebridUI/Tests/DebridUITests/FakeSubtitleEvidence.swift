import Foundation
import DebridCore
@testable import DebridUI

/// A scripted `SubtitleEvidenceProviding`: fixed answers, a call log, and an optional gate that
/// holds the Hebrew search until the test releases it.
final class FakeSubtitleEvidence: SubtitleEvidenceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _searchKeys: [String] = []
    private var _recordAsks = 0
    private var _played: [(MediaSource, [MediaTrack])] = []

    let results: [SubtitleResult]?
    let recordsByKey: [String: VersionSubtitleRecord]
    let stored: SubtitleEvidenceSet
    let gate: HebrewGate?

    init(results: [SubtitleResult]? = nil, records: [String: VersionSubtitleRecord] = [:],
         stored: SubtitleEvidenceSet = .empty, gate: HebrewGate? = nil) {
        self.results = results
        self.recordsByKey = records
        self.stored = stored
        self.gate = gate
    }

    var searchKeys: [String] { lock.lock(); defer { lock.unlock() }; return _searchKeys }
    var recordAsks: Int { lock.lock(); defer { lock.unlock() }; return _recordAsks }
    var played: [(MediaSource, [MediaTrack])] { lock.lock(); defer { lock.unlock() }; return _played }

    func hebrewResults(contentKey: String, query: SubtitleQuery,
                       originalLanguage: String?) async -> [SubtitleResult]? {
        lock.withLock { _searchKeys.append(contentKey) }
        if let gate { await gate.wait() }
        return results
    }

    func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord] {
        lock.withLock { _recordAsks += 1 }
        let keys = Set(sources.map { WatchKey.source($0) })
        return recordsByKey.filter { keys.contains($0.key) }
    }

    func storedEvidence(for sources: [MediaSource], contentKey: String) async -> SubtitleEvidenceSet {
        stored
    }

    func storedHebrewResults(contentKey: String) async -> [SubtitleResult]? { nil }

    func recordPlayback(_ tracks: [MediaTrack], for source: MediaSource) async {
        lock.withLock { _played.append((source, tracks)) }
    }
}

/// Holds an async call until released.
actor HebrewGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func hebrewEventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
