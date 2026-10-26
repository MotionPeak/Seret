import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// The Apple TV's hardware video decoder can lose some Blu-ray REMUXes after a jump — a skip or a
/// scrub while paused, or a resume at a saved place — and keep failing on every frame: the picture
/// freezes and only reopening the film helped (owner, 2026-10-26). The player now reopens the file
/// where it was, decoded in software, and remembers the file.
@MainActor
@Suite struct PlayerDecoderRecoveryTests {
    private func model(_ engine: FakeVideoPlayerEngine, list: SoftwareDecodeList,
                       request: PlaybackRequest = Fixture.request()) -> PlayerModel {
        PlayerModel(request: request, engine: engine, unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _, _ in }, subtitles: nil, softwareDecodes: list)
    }

    private func freshList() -> SoftwareDecodeList {
        SoftwareDecodeList(defaults: UserDefaults(suiteName: "decoder-recovery-\(UUID().uuidString)")!)
    }

    private func playTo(_ seconds: Double, _ engine: FakeVideoPlayerEngine, _ m: PlayerModel) async {
        engine.emit(.state(.playing)); await m.waitForIdleForTesting()
        for t in stride(from: 1.0, through: seconds, by: 1) {
            engine.emit(.time(.init(position: t, duration: 6000))); await m.waitForIdleForTesting()
        }
    }

    @Test func aFailingHardwareDecoderReopensTheFileInSoftwareWhereItWas() async {
        let engine = FakeVideoPlayerEngine(), list = freshList()
        let m = model(engine, list: list)
        m.start(); await m.waitForIdleForTesting()
        await playTo(40, engine, m)
        #expect(engine.softwareDecodingAtLoads == [false])
        engine.emit(.videoDecoderFailing); await m.waitForIdleForTesting()
        await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)
        #expect(engine.softwareDecodingAtLoads == [false, true])
        #expect(engine.seeks.last.map { abs($0 - 40) <= 1 } == true)   // back where it was
    }

    /// The engine is reused for the reopen, and its first tick still carries the OLD media's time —
    /// with no length, as an echo always does. Measured in the simulator: `pos=14.86 dur=0` right
    /// after a reopen aimed at 14 s, taken as "arrived", and the film played from 0:00.
    @Test func theOldMediasTimeIsNotTakenForArrivingAtTheReopenPoint() async {
        let engine = FakeVideoPlayerEngine(), list = freshList()
        let m = model(engine, list: list)
        m.start(); await m.waitForIdleForTesting()
        await playTo(40, engine, m)
        engine.emit(.videoDecoderFailing); await m.waitForIdleForTesting()
        await m.waitForIdleForTesting()
        let seeksBefore = engine.seeks.count
        engine.emit(.time(.init(position: 40.8, duration: 0))); await m.waitForIdleForTesting()   // the echo
        engine.emit(.time(.init(position: 2, duration: 6000))); await m.waitForIdleForTesting()   // really at 2 s
        #expect(engine.seeks.count == seeksBefore + 1)
        #expect(engine.seeks.last.map { abs($0 - 40) <= 1 } == true)
    }

    @Test func theFileIsRememberedForItsNextOpening() async {
        let list = freshList()
        let first = FakeVideoPlayerEngine()
        let m1 = model(first, list: list)
        m1.start(); await m1.waitForIdleForTesting()
        await playTo(5, first, m1)
        first.emit(.videoDecoderFailing); await m1.waitForIdleForTesting()

        let second = FakeVideoPlayerEngine()
        let m2 = model(second, list: list)
        m2.start(); await m2.waitForIdleForTesting()
        #expect(second.softwareDecodingAtLoads == [true])
    }

    @Test func anotherFileStillUsesTheHardwareDecoder() async {
        let list = freshList()
        list.add("some-other-torrent#1")
        let engine = FakeVideoPlayerEngine()
        let m = model(engine, list: list)
        m.start(); await m.waitForIdleForTesting()
        #expect(engine.softwareDecodingAtLoads == [false])
    }

    /// Already in software, a failure report has nothing left to switch: it must not reopen in a loop.
    @Test func aFailureAlreadyInSoftwareDoesNotReopenAgain() async {
        let engine = FakeVideoPlayerEngine(), list = freshList()
        let m = model(engine, list: list)
        m.start(); await m.waitForIdleForTesting()
        await playTo(5, engine, m)
        engine.emit(.videoDecoderFailing); await m.waitForIdleForTesting()
        await m.waitForIdleForTesting()
        await playTo(8, engine, m)
        engine.emit(.videoDecoderFailing); await m.waitForIdleForTesting()
        #expect(engine.loadCount == 2)
    }

    @Test func theListIsBounded() {
        let list = freshList()
        for i in 0..<(SoftwareDecodeList.limit + 20) { list.add("t\(i)#1") }
        #expect(!list.contains("t0#1"))
        #expect(list.contains("t\(SoftwareDecodeList.limit + 19)#1"))
    }
}
