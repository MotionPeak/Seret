import Testing
@testable import DebridCore

/// What display mode the Apple TV should be asked for (QA sweep 2026-10-20, D1).
@Suite struct DisplayModePlanTests {
    private func video(fps: Double? = nil, transfer: VideoTransfer? = nil,
                       codec: String = "V_MPEGH/ISO/HEVC") -> ContainerTrack {
        ContainerTrack(kind: .video, language: nil, codec: codec, frameRate: fps, transfer: transfer)
    }

    @Test func anHDR10RemuxAtFilmRate() {
        let plan = DisplayModePlan.plan(video: video(fps: 23.976, transfer: .pq),
                                        fileName: "Cloverfield.2008.2160p.UHD.BluRay.REMUX.mkv")
        #expect(plan?.range == .hdr10)
        #expect(abs((plan?.refreshRate ?? 0) - 24000.0 / 1001) < 1e-9)
    }

    @Test func theHeaderWinsOverTheName() {
        // A release tagged HDR whose header says BT.709 is SDR — the header describes the bytes.
        let plan = DisplayModePlan.plan(video: video(fps: 25, transfer: .sdr), fileName: "X.2160p.HDR.mkv")
        #expect(plan == DisplayModePlan(refreshRate: 25, range: .sdr))
    }

    @Test func hlgIsItsOwnRange() {
        #expect(DisplayModePlan.plan(video: video(fps: 50, transfer: .hlg), fileName: "x.mkv")?.range == .hlg)
    }

    @Test func aHeaderThatSaysNothingFallsBackToTheReleaseName() {
        #expect(DisplayModePlan.plan(video: video(fps: 23.976), fileName: "Paris.Texas.1984.2160p.DV.HDR.mkv")?.range == .hdr10)
        #expect(DisplayModePlan.plan(video: video(fps: 23.976), fileName: "Film 2160p DoVi WEB-DL.mkv")?.range == .hdr10)
        #expect(DisplayModePlan.plan(video: video(fps: 23.976), fileName: "Film.2160p.HDR10+.mkv")?.range == .hdr10)
        #expect(DisplayModePlan.plan(video: video(fps: 23.976), fileName: "Film.1080p.SDR.mkv")?.range == .sdr)
    }

    /// "HDRip" is a rip, not HDR; "DVDRip" is a DVD, not Dolby Vision.
    @Test func tagsAreWholeWords() {
        #expect(DisplayModePlan.plan(video: video(fps: 25), fileName: "Film.2003.HDRip.mkv") == nil)
        #expect(DisplayModePlan.plan(video: video(fps: 25), fileName: "Film.2003.DVDRip.mkv") == nil)
    }

    @Test func AVCIsSDR() {
        #expect(DisplayModePlan.plan(video: video(fps: 23.976, codec: "V_MPEG4/ISO/AVC"),
                                     fileName: "Her.2013.1080p.BluRay.REMUX.AVC.mkv")?.range == .sdr)
    }

    /// Asking for SDR on an HDR film would be worse than asking for nothing.
    @Test func anUnknownRangeLeavesTheDisplayAlone() {
        #expect(DisplayModePlan.plan(video: video(fps: 23.976), fileName: "Some.Film.2160p.x265.mkv") == nil)
        #expect(DisplayModePlan.plan(video: nil, fileName: "Some.Film.mkv") == nil)
    }

    @Test func aMissingFrameRateWaitsForThePlayers() {
        let plan = DisplayModePlan.plan(video: video(transfer: .pq), fileName: "x.mkv")
        #expect(plan?.refreshRate == nil)
        #expect(plan?.with(fps: 23.976023976).refreshRate == 24000.0 / 1001)
        #expect(plan?.with(fps: nil).refreshRate == nil)
    }

    @Test func ratesSnapToWhatATVOffers() {
        #expect(DisplayModePlan.refreshRate(forFPS: 23.976) == 24000.0 / 1001)
        #expect(DisplayModePlan.refreshRate(forFPS: 29.97) == 30000.0 / 1001)
        #expect(DisplayModePlan.refreshRate(forFPS: 59.94) == 60000.0 / 1001)
        #expect(DisplayModePlan.refreshRate(forFPS: 24) == 24)
        #expect(DisplayModePlan.refreshRate(forFPS: 25) == 25)
        #expect(DisplayModePlan.refreshRate(forFPS: 0) == nil)
        #expect(DisplayModePlan.refreshRate(forFPS: 1000) == nil)
        #expect(DisplayModePlan.refreshRate(forFPS: .nan) == nil)
    }
}
