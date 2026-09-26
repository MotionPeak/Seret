import DebridCore
import Testing
@testable import Seret

@Suite struct VersionTextTests {
    @Test func chipsInOrderSkippingMissing() {
        let full = ParsedRelease(title: "t", resolution: "2160p", source: "BluRay",
                                 videoCodec: "HEVC", audioCodec: "DTS-HD")
        #expect(VersionText.chips(full) == ["2160p", "BluRay", "HEVC", "DTS-HD"])

        let sparse = ParsedRelease(title: "t", resolution: "1080p", videoCodec: "x264")
        #expect(VersionText.chips(sparse) == ["1080p", "x264"])

        #expect(VersionText.chips(ParsedRelease(title: "t")).isEmpty)
    }

    @Test func sizeReadsLikeFinder() {
        #expect(VersionText.size(25_000_000_000) == "25 GB")
        #expect(VersionText.size(6_200_000_000) == "6.2 GB")
    }

    @Test func unknownSizeIsNil() {
        #expect(VersionText.size(nil) == nil)
        #expect(VersionText.size(0) == nil)
    }

    @Test func languagesUpperCasedAndJoined() {
        #expect(VersionText.languages(["en", "he"]) == "EN \u{00B7} HE")
        #expect(VersionText.languages([]) == nil)
    }

    @Test func menuOffersMakeDefaultUnlessItIsTheDefault() {
        let notPreferred = VersionMenu.make(isPreferred: false, hasPreference: true).flatMap { $0 }
        #expect(notPreferred.contains(.makeDefault))

        let preferred = VersionMenu.make(isPreferred: true, hasPreference: true).flatMap { $0 }
        #expect(!preferred.contains(.makeDefault))
    }

    @Test func useBestOnlyWhenAPreferenceExists() {
        let withPreference = VersionMenu.make(isPreferred: false, hasPreference: true).flatMap { $0 }
        #expect(withPreference.contains(.useBestAutomatically))

        let withoutPreference = VersionMenu.make(isPreferred: false, hasPreference: false).flatMap { $0 }
        #expect(!withoutPreference.contains(.useBestAutomatically))
    }

    @Test func removeIsAlwaysLast() {
        for isPreferred in [false, true] {
            for hasPreference in [false, true] {
                let groups = VersionMenu.make(isPreferred: isPreferred, hasPreference: hasPreference)
                #expect(groups.last?.last == .remove)
            }
        }
    }
}
