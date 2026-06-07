import Testing
import Foundation
import DebridCore
@testable import DebridUI

private struct FakeTrailers: TrailerProviding {
    let key: String?
    func trailerKey(tmdbID: Int, kind: MediaKind) async -> String? { key }
}
private struct FakeResolver: TrailerStreamResolving {
    let url: URL?
    func streamURL(youTubeKey: String) async -> URL? { url }
}

@MainActor
@Suite struct TrailerModelTests {
    private func model(key: String?, url: URL?, autoplay: Bool = true) -> TrailerModel {
        TrailerModel(trailers: FakeTrailers(key: key),
                     resolver: FakeResolver(url: url),
                     autoplayEnabled: { autoplay })
    }

    @Test func resolvesToReadyURL() async {
        let m = model(key: "abc", url: URL(string: "https://v/1.mp4")!)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .ready(URL(string: "https://v/1.mp4")!))
        #expect(m.autoplayAllowed == true)
    }

    @Test func noTrailerKeyIsUnavailable() async {
        let m = model(key: nil, url: URL(string: "https://v/1.mp4")!)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .unavailable)
    }

    @Test func extractionFailureIsUnavailable() async {
        let m = model(key: "abc", url: nil)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.state == .unavailable)
        #expect(m.youTubeKey == "abc")   // key kept for the deep-link fallback
    }

    @Test func autoplayDisabledFlagReflectsSetting() async {
        let m = model(key: "abc", url: URL(string: "https://v/1.mp4")!, autoplay: false)
        await m.prepare(tmdbID: 1, kind: .movie)
        #expect(m.autoplayAllowed == false)   // ready, but auto-play suppressed by the setting
    }
}
