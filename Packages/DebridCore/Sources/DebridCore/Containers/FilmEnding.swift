import Foundation

/// Where a film ends, as its own file tells it: when the last line of dialogue leaves the screen,
/// and where the credits begin when a chapter says so.
///
/// Read from the file's index rather than a downloaded subtitle, because the index is the file's
/// own timeline — no other release, cut or frame rate to correct for. Tuned against the indexes of
/// 43 real releases; `FilmEndingTests` keeps the shapes that decided each rule.
public struct FilmEnding: Sendable, Equatable {
    /// When the last line of the film leaves the screen. nil when the subtitle cannot say — none
    /// was indexed, or its lines run on into the credits.
    public let dialogueEnd: Double?
    /// Where a chapter named for the credits begins.
    public let creditsStart: Double?
    /// The subtitle track measured, when the file has one worth reading. Set even when it could not
    /// say where the dialogue ends: the file WAS asked, and a downloaded subtitle — another
    /// release's timing — would be no better an answer.
    public let usableTrack: ContainerTrack?

    public init(dialogueEnd: Double?, creditsStart: Double?, usableTrack: ContainerTrack?) {
        self.dialogueEnd = dialogueEnd
        self.creditsStart = creditsStart
        self.usableTrack = usableTrack
    }

    /// Fewer indexed lines than this is a forced or signs track, or a muxer that did not index its
    /// subtitles at all. A feature's full subtitle runs to a thousand and more.
    static let minimumLines = 200
    /// Consecutive lines further apart than this are separate runs.
    static let runGapSeconds: Double = 60
    /// A run this short this close to the end of the file is credit captions — "subtitles by", a
    /// song title — not the film. Picture subtitles index a line twice (on and off), so eight is
    /// four lines.
    static let strayRunLines = 8
    static let strayRunWindowSeconds: Double = 180
    /// Lines still running this close to the end are captioning the credits: the subtitle cannot
    /// tell where the film stopped.
    static let runsIntoCreditsSeconds: Double = 90
    /// A "credits" chapter before this much of the runtime is the opening titles.
    static let creditsChapterFraction = 0.7

    public static func measure(_ index: MatroskaIndex, duration: Double) -> FilmEnding {
        let credits = duration > 0 ? creditsChapter(in: index.chapters, duration: duration) : nil
        guard duration > 0, let chosen = track(in: index.subtitles) else {
            return FilmEnding(dialogueEnd: nil, creditsStart: credits, usableTrack: nil)
        }
        var lines = chosen.lineEnds

        // A line after the credits begin is a credit, by definition.
        if let credits {
            return FilmEnding(dialogueEnd: lines.last { $0 <= credits }, creditsStart: credits,
                              usableTrack: chosen.track)
        }

        // Peel off short runs in the last three minutes: captions over the credits, not the film.
        while lines.count > strayRunLines {
            var start = lines.count - 1
            while start > 0, lines[start] - lines[start - 1] < runGapSeconds { start -= 1 }
            guard start > 0, lines.count - start <= strayRunLines,
                  lines[start] >= duration - strayRunWindowSeconds else { break }
            lines.removeLast(lines.count - start)
        }
        guard let last = lines.last, last < duration - runsIntoCreditsSeconds else {
            return FilmEnding(dialogueEnd: nil, creditsStart: nil, usableTrack: chosen.track)
        }
        return FilmEnding(dialogueEnd: last, creditsStart: nil, usableTrack: chosen.track)
    }

    /// The full subtitle to read: English before anything else (it is what the viewer asked for,
    /// and an unlabelled track is usually English too), plain before SDH — which goes on captioning
    /// the music after the talking stops — then whichever indexes the most lines.
    static func track(in tracks: [MatroskaIndex.SubtitleTrack]) -> MatroskaIndex.SubtitleTrack? {
        tracks.filter { candidate in
            let name = candidate.track.name?.lowercased() ?? ""
            return !candidate.track.isForced
                && !["commentary", "forced", "signs"].contains { name.contains($0) }
                && candidate.lineEnds.count >= minimumLines
        }
        .max { rank($0) < rank($1) }
    }

    private static func rank(_ candidate: MatroskaIndex.SubtitleTrack) -> (Int, Int, Int) {
        let language = candidate.track.language
        let name = candidate.track.name?.lowercased() ?? ""
        let isSDH = ["sdh", "hearing", "cc"].contains { name.contains($0) }
        return (language == "en" ? 2 : language == nil ? 1 : 0, isSDH ? 0 : 1, candidate.lineEnds.count)
    }

    private static let creditsWords = ["credit", "générique", "generique", "abspann", "end titles", "créditos"]

    static func creditsChapter(in chapters: [MatroskaIndex.Chapter], duration: Double) -> Double? {
        chapters.first { chapter in
            guard chapter.start >= creditsChapterFraction * duration, chapter.start < duration,
                  let title = chapter.title?.lowercased() else { return false }
            return creditsWords.contains { title.contains($0) }
        }?.start
    }
}
