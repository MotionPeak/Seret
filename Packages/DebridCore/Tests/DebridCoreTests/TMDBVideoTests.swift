import Testing
@testable import DebridCore

@Suite struct TMDBVideoTests {
    func v(_ type: String, site: String = "YouTube", key: String = "k") -> TMDBVideo {
        TMDBVideo(key: key, site: site, type: type, name: type)
    }

    @Test func prefersTrailerOverTeaser() {
        let videos = [v("Teaser", key: "teas"), v("Trailer", key: "trail")]
        #expect(videos.firstYouTubeTrailer?.key == "trail")
    }

    @Test func fallsBackToTeaserWhenNoTrailer() {
        #expect([v("Teaser", key: "t")].firstYouTubeTrailer?.key == "t")
    }

    @Test func ignoresNonYouTube() {
        #expect([v("Trailer", site: "Vimeo", key: "x")].firstYouTubeTrailer == nil)
    }

    @Test func nilWhenEmpty() {
        #expect([TMDBVideo]().firstYouTubeTrailer == nil)
    }
}
