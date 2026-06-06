import Testing
@testable import DebridCore

@Suite struct QualityRankTests {
    @Test func resolutionDominatesSourceAndCodec() {
        let p2160 = ParsedRelease(title: "A", resolution: "2160p", source: "HDTV", videoCodec: "h264")
        let p1080 = ParsedRelease(title: "A", resolution: "1080p", source: "REMUX", videoCodec: "HEVC")
        #expect(releaseQualityRank(for: p2160) > releaseQualityRank(for: p1080))
    }

    @Test func sourceBreaksResolutionTies() {
        let remux = ParsedRelease(title: "A", resolution: "1080p", source: "REMUX")
        let webdl = ParsedRelease(title: "A", resolution: "1080p", source: "WEB-DL")
        #expect(releaseQualityRank(for: remux) > releaseQualityRank(for: webdl))
    }

    @Test func codecBreaksSourceTies() {
        let hevc = ParsedRelease(title: "A", resolution: "1080p", source: "BluRay", videoCodec: "HEVC")
        let avc = ParsedRelease(title: "A", resolution: "1080p", source: "BluRay", videoCodec: "x264")
        #expect(releaseQualityRank(for: hevc) > releaseQualityRank(for: avc))
    }

    @Test func unknownFieldsRankZeroTiers() {
        #expect(releaseQualityRank(for: ParsedRelease(title: "A")) == 0)
    }
}
