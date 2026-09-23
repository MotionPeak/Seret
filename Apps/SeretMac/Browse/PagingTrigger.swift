/// Whether an item appearing near the tail of a grid should kick off the next page. Pure so the
/// trigger point is unit-tested without a real `PosterGrid`/`GenreGridStore`.
enum PagingTrigger {
    /// True when `id` is one of the last `within` ids in `ids` — including every item in a grid
    /// shorter than `within`, where there is no meaningful "middle" to wait for. False for an empty
    /// grid or an id that isn't in it.
    static func shouldLoadMore(appeared id: String, in ids: [String], within: Int = 8) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        return index >= ids.count - within
    }
}
