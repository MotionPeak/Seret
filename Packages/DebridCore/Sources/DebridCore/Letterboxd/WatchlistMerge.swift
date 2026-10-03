import Foundation

/// Which lists hold a film.
public struct WatchlistHolders: Sendable, Equatable {
    public let owner: Bool
    public let partner: Bool

    public init(owner: Bool, partner: Bool) {
        self.owner = owner
        self.partner = partner
    }
}

/// Whose watchlist each film came from, hidden films included.
///
/// The merged list deliberately does not say — it is one list on screen — but a removal has to be
/// worded by it: only the owner's Letterboxd can be written to, so taking a film off the partner's
/// list merely hides it here.
public struct WatchlistMembership: Sendable, Equatable {
    private let ownerSlugs: Set<String>
    private let ownerIDs: Set<Int>
    private let partnerSlugs: Set<String>
    private let partnerIDs: Set<Int>

    public static let empty = WatchlistMembership(owner: [], partner: [])

    /// A row the owner removed does not count as held by the owner: removing that film again
    /// writes nothing to the owner's account, and saying it would is the wording this exists to get
    /// right. A partner's hidden rows DO count — the film is still on their Letterboxd, whatever
    /// this device shows.
    public init(owner: [WatchlistEntry], partner: [WatchlistEntry]) {
        let held = owner.filter { !$0.isRemoved }
        ownerSlugs = Set(held.map(\.slug))
        ownerIDs = Set(held.compactMap(\.tmdbID))
        partnerSlugs = Set(partner.map(\.slug))
        partnerIDs = Set(partner.compactMap(\.tmdbID))
    }

    /// Matched by slug OR TMDB id: a film the owner added in Seret carries a placeholder slug, so
    /// only its id can say it is the film the partner already lists.
    public func holders(of entry: WatchlistEntry) -> WatchlistHolders {
        WatchlistHolders(
            owner: ownerSlugs.contains(entry.slug) || entry.tmdbID.map(ownerIDs.contains) == true,
            partner: partnerSlugs.contains(entry.slug) || entry.tmdbID.map(partnerIDs.contains) == true)
    }
}

/// Two watchlists shown as one.
///
/// Pure, and never persisted: each list keeps its own mirror, synced and reconciled exactly as a
/// single list always was, and this only decides what the screen shows. Feeding both crawls into
/// one mirror would have changed every carry rule `WatchlistReconciler` rests on.
public enum WatchlistMerge {
    /// Each list's newest first, alternating, ties to the owner — neither list buried under the
    /// other. Removed rows are kept (screens filter them), and the rows come back numbered 0…n so
    /// any later sort by position agrees with this order.
    public static func combine(owner: [WatchlistEntry],
                               partner: [WatchlistEntry]) -> [WatchlistEntry] {
        let candidates = (owner.map { ($0, false) } + partner.map { (neverPending($0), true) })
            .enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element, rhs.element)
                if a.0.position != b.0.position { return a.0.position < b.0.position }
                if a.1 != b.1 { return !a.1 }          // the owner's row first on a tie
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var output: [(entry: WatchlistEntry, fromPartner: Bool)] = []
        var slotBySlug: [String: Int] = [:]
        var slotByID: [Int: Int] = [:]

        for (entry, fromPartner) in candidates {
            let slot = slotBySlug[entry.slug] ?? entry.tmdbID.flatMap { slotByID[$0] }
            if let slot {
                if prefers(entry, fromPartner: fromPartner, over: output[slot]) {
                    output[slot] = (entry, fromPartner)
                }
                slotBySlug[entry.slug] = slot
                if let id = entry.tmdbID { slotByID[id] = slot }
                continue
            }
            slotBySlug[entry.slug] = output.count
            if let id = entry.tmdbID { slotByID[id] = output.count }
            output.append((entry, fromPartner))
        }

        return output.enumerated().map { index, pair in
            var entry = pair.entry
            entry.position = index
            return entry
        }
    }

    /// The owner's row represents a shared film — it is the one adds and removals act on — unless
    /// the owner hid it and the partner has not. A film is shown if any list holding it still wants
    /// it shown.
    private static func prefers(_ candidate: WatchlistEntry, fromPartner: Bool,
                                over current: (entry: WatchlistEntry, fromPartner: Bool)) -> Bool {
        // Two rows of one film from the same list do not happen; keep the first rather than guess.
        guard fromPartner != current.fromPartner else { return false }
        let ownerRow = fromPartner ? current.entry : candidate
        let partnerRow = fromPartner ? candidate : current.entry
        let partnerWins = ownerRow.isRemoved && !partnerRow.isRemoved
        return fromPartner ? partnerWins : !partnerWins
    }

    /// Nothing ever pushes a partner's row, so nothing about it may read as pending. A pending
    /// mark would make the toggle treat re-adding a film hidden here as cancelling a write that
    /// never existed — and then not send the owner's real add.
    private static func neverPending(_ entry: WatchlistEntry) -> WatchlistEntry {
        var entry = entry
        entry.removalPushedAt = entry.removedAt
        entry.addedLocallyAt = nil
        entry.addPushedAt = nil
        return entry
    }
}
