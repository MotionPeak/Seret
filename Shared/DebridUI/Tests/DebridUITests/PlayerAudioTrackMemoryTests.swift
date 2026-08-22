import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// libvlc's load-time options can name a LANGUAGE but not a codec, and a REMUX lists its lossless
/// track first — so on a file carrying both DTS-HD MA and AC-3 in English it opens the one this
/// hardware handles worst, and the model corrects it once the tracks appear. That correction costs
/// a `killing decoder` → rebuild, which is an audible drop-out.
///
/// The track list is only knowable by playing (parsing the media first was built, measured on the
/// Apple TV, and reverted — libvlc never finishes preparsing an RD-hosted MKV). So the file itself
/// teaches us: the track that worked is remembered against that exact source and named at load next
/// time. Measured on the device, naming it up front takes `killing decoder` from 1 to 0 and the
/// audio decoders built during startup from 4 to 2.
@MainActor
@Suite struct PlayerAudioTrackMemoryTests {

    private func remuxTracks() -> [MediaTrack] {
        [MediaTrack(id: "audio/2", kind: .audio, name: "DTS-HD MA", language: "en", codec: "dts"),
         MediaTrack(id: "audio/3", kind: .audio, name: "AC-3", language: "en", codec: "a52")]
    }

    private func makeModel(engine: FakeVideoPlayerEngine,
                           prefs: FakeTrackPreferences) -> PlayerModel {
        PlayerModel(request: Fixture.request(), engine: engine,
                    unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                    recordProgress: { _, _, _, _ in },
                    subtitles: nil,
                    trackPreferences: prefs)
    }

    /// The correction the model makes today is worth remembering — it is the answer to "which track
    /// should have been opened", and it is only ever learned the expensive way.
    @Test func overridingTheEnginesAudioChoiceRemembersItForThatFile() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let model = makeModel(engine: engine, prefs: prefs)
        model.start()
        await model.waitForIdleForTesting()

        engine.audioTracks = remuxTracks()
        engine.emit(.tracksChanged)
        await model.waitForIdleForTesting()

        #expect(model.selectedAudioID == "audio/3")            // AC-3 beats DTS
        #expect(prefs.recordedTrackIDs[Fixture.sourceKey] == "audio/3")
    }

    /// …and named at load, so libvlc opens it directly instead of opening DTS and being corrected.
    @Test func aRememberedTrackIsNamedAtLoad() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        prefs.recordedTrackIDs[Fixture.sourceKey] = "audio/3"
        let model = makeModel(engine: engine, prefs: prefs)
        model.start()
        await model.waitForIdleForTesting()

        #expect(engine.loadedAudioTrackID == "audio/3")
    }

    /// A file we have never played names nothing — the engine keeps its own judgement, and the
    /// existing correction remains the safety net.
    @Test func anUnseenFileNamesNoTrack() async {
        let engine = FakeVideoPlayerEngine()
        let model = makeModel(engine: engine, prefs: FakeTrackPreferences())
        model.start()
        await model.waitForIdleForTesting()

        #expect(engine.loadedAudioTrackID == nil)
    }

    /// A manual pick is the strongest signal there is about this file, so it is remembered too.
    @Test func aManualPickIsRememberedForThatFile() async {
        let engine = FakeVideoPlayerEngine()
        let prefs = FakeTrackPreferences()
        let model = makeModel(engine: engine, prefs: prefs)
        model.start()
        await model.waitForIdleForTesting()
        engine.audioTracks = remuxTracks()
        engine.emit(.tracksChanged)
        await model.waitForIdleForTesting()

        model.selectAudio(id: "audio/2")
        #expect(prefs.recordedTrackIDs[Fixture.sourceKey] == "audio/2")
    }
}
