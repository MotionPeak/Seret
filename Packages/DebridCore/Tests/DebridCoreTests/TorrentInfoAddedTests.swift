import Testing
import Foundation
@testable import DebridCore

@Suite struct TorrentInfoAddedTests {
    @Test func decodesAddedWhenPresent() throws {
        let json = #"{"id":"abc","filename":"f","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[],"links":[],"added":"2026-06-01T10:30:00.000Z"}"#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.added == "2026-06-01T10:30:00.000Z")
    }

    @Test func addedIsNilWhenMissing() throws {
        let json = #"{"id":"abc","filename":"f","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[],"links":[]}"#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.added == nil)
    }
}
