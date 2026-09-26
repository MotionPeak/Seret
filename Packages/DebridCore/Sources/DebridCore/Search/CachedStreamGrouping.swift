/// Grouping a ranked version list for display.
///
/// Nothing is filtered out of a version list — the oversized releases are ranked to the bottom and
/// were simply getting lost among thirty-odd rows, which reads as "the big ones aren't there".
/// Splitting them into a section of their own keeps them one glance away while leaving the ranking,
/// and therefore the default pick, exactly as it was.
public extension Array where Element == CachedStream {
    /// Split into the oversized releases and everything else, preserving the incoming order within
    /// each group.
    ///
    /// Order matters: the list arrives already ranked, and reordering inside a group would stop the
    /// best pick being the first row. `episodesInSeason` lets a season pack be judged per episode,
    /// exactly as the ranking judges it.
    func splitOversized(episodesInSeason: Int?) -> (larger: [CachedStream], rest: [CachedStream]) {
        var larger: [CachedStream] = []
        var rest: [CachedStream] = []
        for stream in self {
            let shape = ReleaseShape.of(stream.parsed, episodes: episodesInSeason)
            if sizeClass(bytes: stream.sizeBytes, resolution: stream.parsed.resolution,
                         shape: shape) == .over {
                larger.append(stream)
            } else {
                rest.append(stream)
            }
        }
        return (larger, rest)
    }

    /// The list as it is drawn: every release Real-Debrid can play at once above every one that
    /// has to download first, and each block split into its oversized releases and the rest.
    ///
    /// The ranking judges quality, size and Hebrew, never availability, so on its own it
    /// interleaves the two. This only regroups: order inside every part is the ranking's, and a
    /// block with nothing in it is left out rather than drawn as a heading over no rows.
    func groupedByAvailability(episodesInSeason: Int?) -> [VersionGroup] {
        let instant = filter(\.isCached).splitOversized(episodesInSeason: episodesInSeason)
        let download = filter { !$0.isCached }.splitOversized(episodesInSeason: episodesInSeason)
        return [VersionGroup(availability: .instant, larger: instant.larger, rest: instant.rest),
                VersionGroup(availability: .download, larger: download.larger, rest: download.rest)]
            .filter { !$0.larger.isEmpty || !$0.rest.isEmpty }
    }
}

/// One block of a version list: the releases that play right away, or the ones that download to
/// Real-Debrid first.
public struct VersionGroup: Sendable, Equatable, Identifiable {
    public enum Availability: Sendable, Equatable, Hashable {
        /// Real-Debrid already has it: it plays at once.
        case instant
        /// Real-Debrid has to fetch it first.
        case download
    }

    public let availability: Availability
    /// Oversized releases, in ranking order.
    public let larger: [CachedStream]
    /// Everything else, in ranking order.
    public let rest: [CachedStream]

    public var id: Availability { availability }

    public init(availability: Availability, larger: [CachedStream], rest: [CachedStream]) {
        self.availability = availability
        self.larger = larger
        self.rest = rest
    }
}
