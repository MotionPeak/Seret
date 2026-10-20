import Foundation

/// Where focus goes when the focused tile of a rail page leaves it — marked watched, removed, its
/// download finished. tvOS itself leaves nothing focused in that case, so the page picks a
/// neighbour and moves focus there.
///
/// Keys are `"<rail>/<id>"`, listed rail by rail in screen order; the rail is everything before the
/// first `/`.
public enum RailFocusNeighbour {
    /// The tile now at `gone`'s place in the same rail (the one after it, or the new last). With
    /// the rail emptied, the first tile of the nearest rail below it, else of the nearest above.
    /// Nil only when nothing is left at all.
    public static func of(_ gone: String, old: [String], new: [String]) -> String? {
        let goneRail = rail(gone)
        let sameRail = new.filter { rail($0) == goneRail }
        if !sameRail.isEmpty {
            let index = old.filter { rail($0) == goneRail }.firstIndex(of: gone) ?? 0
            return sameRail[min(index, sameRail.count - 1)]
        }
        var oldRails: [Substring] = []
        for key in old where oldRails.last != rail(key) { oldRails.append(rail(key)) }
        guard let position = oldRails.firstIndex(of: goneRail) else { return new.first }
        let below = oldRails[(position + 1)...]
        let above = oldRails[..<position].reversed()
        for candidate in Array(below) + Array(above) {
            if let first = new.first(where: { rail($0) == candidate }) { return first }
        }
        return new.first
    }

    private static func rail(_ key: String) -> Substring { key.prefix { $0 != "/" } }
}
