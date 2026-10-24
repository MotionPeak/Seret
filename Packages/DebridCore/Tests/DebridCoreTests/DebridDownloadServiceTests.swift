import Testing
import Foundation
@testable import DebridCore

/// Pure: the download service starts the background download on whatever client it is handed —
/// for the composite, the add target.
@Suite struct DebridDownloadServiceTests {
    @Test func startsTheDownloadOnTheAddTarget() async throws {
        let log = FakeDebridCallLog()
        let composite = CompositeDebridClient(
            clients: [FakeDebridClient(provider: .realDebrid, log: log),
                      FakeDebridClient(provider: .torBox, log: log)],
            addTarget: .torBox)

        let info = try await DebridDownloadService(client: composite).startDownload(infoHash: "abc")

        #expect(info.id == "tb:new")
        #expect(info.status == "downloading")
        #expect(log.all == ["torBox.addForDownload(abc)"])
    }
}
