import Testing
import Foundation
@testable import DebridCore

/// Telling dialogue apart from everything else in a film mix.
///
/// Loudness cannot: measured on a real action film, the loud passages are gunfire and score with no
/// subtitles while the dialogue is quiet, so a loudness envelope correlated NEGATIVELY with the
/// subtitle that matched it. What separates speech is not how loud a moment is but where it sits —
/// a film mix puts dialogue in the CENTRE channel by convention and spreads music and effects
/// across the others.
@Suite struct VoiceActivityTests {

    /// Dialogue: centre carries it, the mix is barely louder than the centre alone — and that
    /// scores above the same centre level spread across the whole mix. The score is relative, so
    /// what it must get right is the ORDER, not any particular number.
    @Test func centreDominatedAudioOutscoresTheSameLevelSpreadWide() {
        let focused = VoiceActivity.score(centre: [0.5], mix: [0.55])
        let spread = VoiceActivity.score(centre: [0.5], mix: [2.0])

        #expect(focused[0] > spread[0] * 3)
    }

    /// An explosion: loud everywhere, centre no more than its share.
    @Test func aLoudWideSoundScoresLowDespiteItsVolume() {
        let quiet = VoiceActivity.score(centre: [0.2], mix: [0.22])      // quiet dialogue
        let loud = VoiceActivity.score(centre: [0.4], mix: [2.0])        // loud effects

        #expect(quiet[0] > loud[0], "quiet dialogue must beat loud effects")
    }

    /// Silence is silence, however the channels divide it — a ratio alone would call a
    /// near-silent frame pure speech, since a whisper of centre over a whisper of everything is
    /// still dominance.
    @Test func silenceScoresNothing() {
        let score = VoiceActivity.score(centre: [0.0005], mix: [0.0006])
        #expect(score[0] < 0.01)
    }

    /// The shape that matters: over a run of frames, the dialogue ones must come out on top even
    /// when the effects are several times louder.
    @Test func dialogueOutranksLouderEffectsAcrossAWindow() {
        //      0-2: quiet dialogue      3-5: loud wide action      6: silence
        let centre: [Float] = [0.30, 0.28, 0.32, 0.50, 0.45, 0.55, 0.001]
        let mix: [Float]    = [0.33, 0.31, 0.35, 2.40, 2.20, 2.60, 0.002]

        let score = VoiceActivity.score(centre: centre, mix: mix)
        let ranked = score.indices.sorted { score[$0] > score[$1] }

        #expect(Set(ranked.prefix(3)) == Set([0, 1, 2]))
    }

    @Test func mismatchedOrEmptyInputIsSafe() {
        #expect(VoiceActivity.score(centre: [], mix: []).isEmpty)
        #expect(VoiceActivity.score(centre: [1, 2, 3], mix: [1]).count == 1)
        #expect(VoiceActivity.score(centre: [1], mix: [1, 2, 3]).count == 1)
    }

    /// A stereo source has no real centre — libvlc synthesises one as (L+R)/2, so centre tracks the
    /// mix exactly and dominance carries no information. It must degrade to loudness rather than
    /// to a constant, which would make every frame identical and the correlation meaningless.
    @Test func aSyntheticCentreDegradesToLoudness() {
        let centre: [Float] = [0.1, 0.5, 0.2, 0.9]
        let mix = centre.map { $0 * 1.0001 }           // centre IS the mix

        let score = VoiceActivity.score(centre: centre, mix: mix)

        #expect(score[3] > score[1], "louder frames must still rank higher")
        #expect(score[1] > score[0])
    }
}

/// A film mix's dialogue lives between roughly 300 Hz and 3.4 kHz. Removing what is outside that
/// takes the bass of a score and the sparkle of effects out of the centre channel before any of it
/// is measured.
@Suite struct SpeechBandTests {

    private func tone(_ hz: Double, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { Float(sin(2 * .pi * hz * Double($0) / sampleRate)) }
    }

    @Test func aSpeechRangeToneSurvives() {
        var f = SpeechBandFilter(sampleRate: 16000)
        let out = tone(1000, sampleRate: 16000, count: 4000).map { f.process($0) }
        let energy = out.suffix(2000).reduce(0) { $0 + $1 * $1 } / 2000

        #expect(energy > 0.05)
    }

    private func energy(_ hz: Double) -> Float {
        var f = SpeechBandFilter(sampleRate: 16000)
        let out = tone(hz, sampleRate: 16000, count: 6000).map { f.process($0) }
        return out.suffix(2000).reduce(0) { $0 + $1 * $1 } / 2000
    }

    /// Speech beats both neighbours by a wide margin — that ordering is the whole purpose, and a
    /// ratio is what the measurement downstream actually depends on.
    @Test func theSpeechBandIsFavouredOverBassAndTreble() {
        #expect(energy(1000) > energy(50) * 20)
        #expect(energy(1000) > energy(7000) * 20)
    }

    /// …and the band itself is broad enough to hold a voice, not a single tone.
    @Test func theWholeSpeechRangePassesReasonablyEvenly() {
        let mid = energy(1000)
        #expect(energy(500) > mid * 0.2)
        #expect(energy(2500) > mid * 0.2)
    }
}
