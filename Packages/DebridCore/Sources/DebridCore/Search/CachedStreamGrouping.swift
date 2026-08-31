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
}
