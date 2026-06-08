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

    @Test func trueHDIsDemotedBelowPlayableAudio() {
        // A silent-on-iOS TrueHD 2160p REMUX must rank below a playable 1080p WEB-DL.
        let truehd = ParsedRelease(title: "A", resolution: "2160p", source: "REMUX",
                                   videoCodec: "HEVC", audioCodec: "TrueHD")
        let eac3 = ParsedRelease(title: "A", resolution: "1080p", source: "WEB-DL",
                                 videoCodec: "HEVC", audioCodec: "EAC3")
        #expect(releaseQualityRank(for: truehd) < releaseQualityRank(for: eac3))
    }

    @Test func playableAudioWinsEvenAtLowerResolution() {
        // The user wants sound: a playable 480p beats a silent 2160p TrueHD REMUX.
        let truehd = ParsedRelease(title: "A", resolution: "2160p", source: "REMUX", audioCodec: "TrueHD")
        let aac = ParsedRelease(title: "A", resolution: "480p", audioCodec: "AAC")
        #expect(releaseQualityRank(for: aac) > releaseQualityRank(for: truehd))
    }

    @Test func nonTrueHDAudioDoesNotChangeTheRank() {
        // Only TrueHD is penalized; a playable codec leaves the (video-only) rank untouched.
        let eac3 = ParsedRelease(title: "A", resolution: "1080p", source: "WEB-DL", audioCodec: "EAC3")
        let noAudio = ParsedRelease(title: "A", resolution: "1080p", source: "WEB-DL")
        #expect(releaseQualityRank(for: eac3) == releaseQualityRank(for: noAudio))
    }
}
