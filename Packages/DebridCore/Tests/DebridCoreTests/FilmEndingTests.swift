import Testing
@testable import DebridCore

/// Where a film ends, read from the file's own subtitle index and chapters.
///
/// Every timeline here is the tail of a REAL release's index (seconds, the last seven minutes),
/// measured off the files Shahar watched in September 2026. Each one is a shape the rule has to get
/// right; together they are why the rule is what it is.
@Suite struct FilmEndingTests {

    private func english(_ ends: [Double], name: String? = nil, forced: Bool = false,
                         language: String? = "en") -> MatroskaIndex.SubtitleTrack {
        // Padded with a film's worth of lines in front, so a track looks like full dialogue.
        let body = stride(from: 600.0, to: (ends.first ?? 600) - 1, by: 6).map { $0 }
        return .init(track: ContainerTrack(kind: .subtitle, language: language, codec: "S_HDMV/PGS",
                                           name: name, isForced: forced),
                     lineEnds: body + ends)
    }

    private func end(_ tracks: [MatroskaIndex.SubtitleTrack], chapters: [MatroskaIndex.Chapter] = [],
                     duration: Double) -> FilmEnding {
        FilmEnding.measure(MatroskaIndex(subtitles: tracks, chapters: chapters), duration: duration)
    }

    // MARK: - The last line

    /// The Nice Guys: dialogue to 1:50:49, then one stray entry — "subtitles by" — three seconds
    /// before the file ends. It is not the film.
    @Test func aStrayEntryAtTheVeryEndIsNotTheFilm() {
        let tail: [Double] = [6539.6, 6542.3, 6544.8, 6548.9, 6551.2, 6552.6, 6556.5, 6559.5, 6564.1,
                              6567.1, 6571.0, 6574.3, 6577.1, 6578.8, 6581.4, 6586.0, 6589.7, 6596.4,
                              6600.4, 6603.7, 6606.2, 6607.9, 6609.2, 6610.8, 6613.3, 6618.5, 6621.3,
                              6623.9, 6625.7, 6627.6, 6629.2, 6630.9, 6632.5, 6633.7, 6636.4, 6637.8,
                              6639.9, 6642.8, 6645.6, 6647.2, 6649.6, 6955.2]
        let measured = end([english(tail)], duration: 6957.1)
        #expect(measured.dialogueEnd == 6649.6)
        #expect(measured.creditsStart == nil)
    }

    /// One Flew Over the Cuckoo's Nest: two sparse runs after the escape. The one in the last three
    /// minutes is credits; the one before it might be the film, and late is the side to err on.
    @Test func onlyTheLastThreeMinutesAreTakenForCredits() {
        let tail: [Double] = [7623.0, 7626.0, 7628.0, 7631.2, 7640.4, 7643.2, 7663.9, 7665.4,
                              7832.4, 7835.7, 7835.9, 7838.5, 8016.0, 8018.0, 8018.2, 8020.2]
        #expect(end([english(tail)], duration: 8022.7).dialogueEnd == 7838.5)
    }

    /// Mulholland Drive ends on one word — "Silencio" — after a minute of silence. A final line is
    /// still a line of the film when it is more than three minutes from the end of the file.
    @Test func aLoneFinalLineBeforeTheCreditsIsKept() {
        let tail: [Double] = [8433.0, 8435.7, 8435.8, 8438.4, 8443.4, 8446.0, 8455.3, 8457.5, 8457.6,
                              8460.1, 8462.0, 8465.0, 8465.1, 8467.1, 8469.0, 8472.8, 8481.3, 8484.6,
                              8492.8, 8494.4, 8499.5, 8501.1, 8506.2, 8507.7, 8575.8, 8578.2]
        #expect(end([english(tail)], duration: 8840.3).dialogueEnd == 8578.2)
    }

    @Test func americanHistoryX() {
        let tail: [Double] = [6777.4, 6779.7, 6781.3, 6787.0, 6789.5, 6794.0, 6798.4, 6814.6, 6816.9,
                              6832.4, 6834.8, 6848.3, 6850.9, 6853.8, 6856.0, 6859.5, 6861.9, 6867.9,
                              6870.4, 6875.1, 6878.0, 6882.9, 6885.5, 6887.8, 6891.3, 6896.3, 6901.1,
                              7131.2]
        #expect(end([english(tail)], duration: 7133.5).dialogueEnd == 6901.1)
    }

    /// Good Will Hunting: the English track runs to nine seconds from the end — it captions the song
    /// over the credits. Lines that never stop say nothing about where the film did.
    @Test func linesRunningToTheEndOfTheFileAreNotEvidence() {
        let tail: [Double] = stride(from: 7184.8, through: 7584.3, by: 3.5).map { $0 }
        let measured = end([english(tail)], duration: 7593.5)
        #expect(measured.dialogueEnd == nil)
        #expect(measured.usableTrack != nil, "a track WAS read — the file just could not say")
    }

    // MARK: - Chapters

    /// Goodfellas: a chapter called "End Credits" at 2:20:33. The file's author marked it; nothing
    /// is more exact.
    @Test func anEndCreditsChapterIsWhereTheCreditsStart() {
        let tail: [Double] = [8350.9, 8355.8, 8368.1, 8378.5, 8387.0, 8711.3, 8713.3]
        let measured = end([english(tail)],
                           chapters: [.init(start: 0, title: "Chapter 1"),
                                      .init(start: 8433.1, title: "End Credits")],
                           duration: 8721.8)
        #expect(measured.creditsStart == 8433.1)
        #expect(measured.dialogueEnd == 8387.0)
    }

    /// Bugonia's SDH track captions the song over its final montage and on into the credits; lines
    /// after the credits chapter are the credits by definition.
    @Test func linesAfterTheCreditsChapterAreNotTheFilm() {
        let tail: [Double] = [6600, 6700, 6800, 6900, 7000, 7050]
        let measured = end([english(tail)], chapters: [.init(start: 6713, title: "End Credits")],
                           duration: 7094)
        #expect(measured.dialogueEnd == 6700)
        #expect(measured.creditsStart == 6713)
    }

    @Test func creditsChaptersInOtherLanguagesCount() {
        for title in ["Credits", "Générique de fin", "Abspann", "Créditos finales", "END CREDITS"] {
            let measured = end([], chapters: [.init(start: 6500, title: title)], duration: 7000)
            #expect(measured.creditsStart == 6500, "\(title)")
        }
    }

    /// "Credits" is also an OPENING chapter on some discs.
    @Test func aCreditsChapterEarlyInTheFilmIsTheOpeningTitles() {
        let measured = end([], chapters: [.init(start: 30, title: "Opening Credits")], duration: 7000)
        #expect(measured.creditsStart == nil)
    }

    // MARK: - Which track

    /// Bugonia carries both: the plain English track stops with the dialogue, the SDH one goes on
    /// captioning the music. The plain one says where the talking ends.
    @Test func plainEnglishIsPreferredOverSDH() {
        let sdh = english([6600, 6900, 7000], name: "English (SDH)")
        let plain = english([6290, 6299], name: "English")
        #expect(end([sdh, plain], duration: 7094).dialogueEnd == 6299)
        #expect(end([plain, sdh], duration: 7094).dialogueEnd == 6299)
    }

    @Test func forcedAndCommentaryTracksAreNeverUsed() {
        let forced = english([6290], forced: true)
        let commentary = english([6400], name: "Commentary with the director")
        let measured = end([forced, commentary], duration: 7000)
        #expect(measured.usableTrack == nil)
        #expect(measured.dialogueEnd == nil)
    }

    /// Parasite's English track is "forced" — its only full subtitle is French. When the lines are
    /// spoken does not depend on the language they are written in.
    @Test func withNoEnglishAnyFullTrackSaysWhenTheDialogueEnds() {
        let french = english([7600, 7620], language: "fr")
        #expect(end([french], duration: 7914).dialogueEnd == 7620)
    }

    /// Predestination's REMUX names twenty subtitle tracks and indexes none of their lines.
    @Test func aTrackWithAHandfulOfIndexedLinesIsNotAFullSubtitle() {
        let sparse = MatroskaIndex.SubtitleTrack(
            track: ContainerTrack(kind: .subtitle, language: "en"), lineEnds: [100, 2000, 5000])
        #expect(end([sparse], duration: 5868).usableTrack == nil)
    }
}
