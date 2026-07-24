import Testing
import Foundation
@testable import DebridCore

@Suite struct SubtitleMatchTests {
    private let fileName = "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.HDR.H265-FLUX.mkv"

    private func result(_ release: String, hash: Bool? = nil, downloads: Int = 100,
                        fps: Double? = nil, trusted: Bool? = nil,
                        ai: Bool? = nil, id: Int = 0) -> SubtitleResult {
        SubtitleResult(fileID: id, language: "he", release: release,
                       fileName: release + ".srt", downloadCount: downloads, fps: fps,
                       trusted: trusted, aiTranslated: ai, moviehashMatch: hash)
    }

    @Test func aHashMatchOutranksEverything() {
        let hashed = result("Some.Totally.Different.Release-XYZ", hash: true, downloads: 1, id: 1)
        let popular = result("Dune.Part.Two.2024.2160p.WEB-DL.HDR.H265-FLUX", downloads: 999_999, id: 2)
        let ranked = SubtitleMatch.rank([popular, hashed], against: fileName, videoFPS: nil)
        #expect(ranked.first?.result == hashed)
        #expect(ranked.first?.quality == .perfect)
    }

    @Test func theSameReleaseGroupOutranksAStrangerWithMoreDownloads() {
        let sameGroup = result("Dune.Part.Two.2024.1080p.WEB-DL.H264-FLUX", downloads: 10, id: 1)
        let stranger = result("Dune.Part.Two.2024.720p.BluRay.x264-YTS", downloads: 500_000, id: 2)
        let ranked = SubtitleMatch.rank([stranger, sameGroup], against: fileName, videoFPS: nil)
        #expect(ranked.first?.result == sameGroup)
        #expect(ranked.first?.quality == .good)
    }

    @Test func downloadsBreakTiesBetweenEquallyPoorMatches() {
        let quiet = result("Unrelated.Release.One-AAA", downloads: 5, id: 1)
        let loud = result("Unrelated.Release.Two-BBB", downloads: 5000, id: 2)
        let ranked = SubtitleMatch.rank([quiet, loud], against: fileName, videoFPS: nil)
        #expect(ranked.first?.result == loud)
    }

    @Test func anExactReleaseNameIsAStrongMatchWithoutAHash() {
        let exact = result("Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.HDR.H265-FLUX", id: 1)
        let ranked = SubtitleMatch.rank([exact], against: fileName, videoFPS: nil)
        #expect(ranked.first?.quality == .good)
        #expect(ranked.first?.reasons.contains(.sameGroup) == true)
    }

    @Test func anFPSMismatchDemotesAnOtherwiseCloseMatch() {
        let right = result("Dune.Part.Two.2024.2160p.WEB-DL.HDR.H265-FLUX", fps: 23.976, id: 1)
        let wrong = result("Dune.Part.Two.2024.2160p.WEB-DL.HDR.H265-FLUX", fps: 25.0, id: 2)
        let ranked = SubtitleMatch.rank([wrong, right], against: fileName, videoFPS: 23.976)
        #expect(ranked.first?.result == right)
    }

    @Test func aiTranslationIsPenalised() {
        let human = result("Dune.Part.Two.2024.720p.WEB-X", downloads: 10, ai: false, id: 1)
        let machine = result("Dune.Part.Two.2024.720p.WEB-X", downloads: 10, ai: true, id: 2)
        let ranked = SubtitleMatch.rank([machine, human], against: fileName, videoFPS: nil)
        #expect(ranked.first?.result == human)
    }

    @Test func rankingIsStableAndLosesNothing() {
        let all = (0..<7).map { result("Release.Number.\($0)-GRP", downloads: $0 * 10, id: $0) }
        #expect(SubtitleMatch.rank(all, against: fileName, videoFPS: nil).count == 7)
    }

    @Test func anEmptyListRanksToNothing() {
        #expect(SubtitleMatch.rank([], against: fileName, videoFPS: nil).isEmpty)
    }

    @Test func aSourceRebuildsACanonicalReleaseName() {
        let source = MediaSource(
            torrentID: "t", fileID: nil, restrictedLink: "rd://x",
            parsed: ParsedRelease(title: "Dune Part Two", year: 2024, resolution: "2160p",
                                  source: "WEB-DL", videoCodec: "H265", releaseGroup: "FLUX"))
        #expect(source.releaseNameForMatching == "Dune.Part.Two.2024.2160p.WEB-DL.H265-FLUX")
    }
}
