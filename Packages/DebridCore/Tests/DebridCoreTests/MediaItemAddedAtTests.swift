import Testing
import Foundation
@testable import DebridCore

@Suite struct MediaItemAddedAtTests {
    @Test func storesAndRoundTripsAddedAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: nil, sources: [], seasons: [], addedAt: date)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MediaItem.self, from: data)
        #expect(decoded.addedAt == date)
    }

    @Test func decodesOldSnapshotWithoutAddedAt() throws {
        // Old cached snapshots have no `addedAt` key — must decode to nil, not throw.
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: nil, sources: [], seasons: [])
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        dict.removeValue(forKey: "addedAt")
        let decoded = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(decoded.addedAt == nil)
        #expect(decoded.id == "movie:x")
    }
}
