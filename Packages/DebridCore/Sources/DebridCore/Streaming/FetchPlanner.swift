import Foundation

/// A fetch in flight, as the planner needs to see it: where its next byte will land.
struct FetchSnapshot: Sendable, Equatable {
    let id: Int
    let position: Int64
}

/// What to do about a read the RAM cache cannot answer yet.
enum ReadDecision: Sendable, Equatable {
    case serve
    case loadFromIndex
    /// A fetch in flight will reach the read within the wait window.
    case wait(fetch: Int)
    /// Start a fetch at `start` (and at `lookBehind`, when set), cancelling `cancel` first.
    case fetch(start: Int64, lookBehind: Int64?, cancel: [Int])
}

/// Pure policy: which bytes to fetch, and when read-ahead pauses. Everything here is a function
/// of its inputs, so the rules can be tested against the recorded walks directly.
struct FetchPlanner: Sendable {
    let budget: StreamCacheBudget

    init(budget: StreamCacheBudget) { self.budget = budget }

    func decide(offset: Int64, cached: Bool, inIndex: Bool, fetches: [FetchSnapshot],
                lastRead: Int64?, isChunkCached: (Int) -> Bool) -> ReadDecision {
        if cached { return .serve }
        if inIndex { return .loadFromIndex }
        // Reading through on a live connection beats a ~460ms reconnect for anything close.
        let window = Int64(budget.waitWindowBytes)
        if let nearest = fetches
            .filter({ $0.position <= offset && offset - $0.position <= window })
            .max(by: { $0.position < $1.position }) {
            return .wait(fetch: nearest.id)
        }
        let size = Int64(budget.chunkSize)
        let start = (offset / size) * size
        // Behind the last read: a rewind, or the demuxer stepping back cluster by cluster for a
        // keyframe. Its next steps will be further back, so start a second fetch behind this one.
        var lookBehind: Int64?
        if let lastRead, offset < lastRead, start > 0 {
            let candidate = max(0, ((start - Int64(budget.lookBehindBytes)) / size) * size)
            if !isChunkCached(Int(candidate / size)) { lookBehind = candidate }
        }
        let needed = lookBehind == nil ? 1 : 2
        let excess = fetches.count + needed - budget.maxFetches
        let cancel = excess > 0
            ? fetches.sorted { abs($0.position - offset) > abs($1.position - offset) }
                .prefix(excess).map(\.id)
            : []
        return .fetch(start: start, lookBehind: lookBehind, cancel: cancel)
    }

    /// Read-ahead has reached its cap in front of where libvlc is reading.
    func shouldSuspend(position: Int64, lastReadEnd: Int64) -> Bool {
        position - lastReadEnd >= Int64(budget.readAheadBytes)
    }

    /// libvlc has consumed half the read-ahead: resume, so the connection refills early.
    func shouldResume(position: Int64, lastReadEnd: Int64) -> Bool {
        position - lastReadEnd < Int64(budget.readAheadBytes / 2)
    }
}
