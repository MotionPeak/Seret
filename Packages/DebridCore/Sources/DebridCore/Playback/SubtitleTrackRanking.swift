import Foundation

public extension MediaTrack {
    /// Whether this subtitle track is a sequence of pre-rendered IMAGES rather than text.
    ///
    /// Blu-ray rips carry `bdpg` (PGS) and DVD rips `spu `/VobSub. The distinction is not cosmetic:
    /// a bitmap track ignores every font, size and colour preference the app offers, because those
    /// apply to text this app renders and a bitmap arrives already drawn; it cannot be corrected by
    /// `SubtitleRetimer`, which rewrites cue timestamps in a file we own; and every cue is an image
    /// to decode and composite, which is the first thing to suffer when the pipeline is loaded.
    ///
    /// An unknown codec is treated as text. Guessing "bitmap" would demote a good track on no
    /// evidence, and being wrong that way costs more than failing to promote one.
    var isBitmapSubtitle: Bool {
        guard let codec else { return false }
        return Self.bitmapSubtitleCodecs.contains(
            codec.trimmingCharacters(in: .whitespaces).lowercased())
    }

    private static let bitmapSubtitleCodecs: Set<String> = [
        "bdpg",   // Blu-ray PGS
        "pgs",
        "hdmv",
        "spu",    // DVD VobSub
        "spub",
        "dvbs",   // DVB
        "dvds",
        "xsub",   // DivX
        "cvd",
        "ogt",
    ]
}

public extension Array where Element == MediaTrack {
    /// The best subtitle track in `language`: text before bitmap, and otherwise the order the
    /// container lists them in.
    ///
    /// Selection used to be `first(where: { $0.language == lang })`, and on a REMUX the bitmap
    /// tracks are listed first — so the app reliably chose the one that ignores the viewer's font
    /// settings, cannot be retimed, and drops cues under load.
    func bestSubtitle(forLanguage language: String) -> MediaTrack? {
        let matching = filter { $0.kind == .subtitle && $0.matchesLanguage(language) }
        return matching.first { !$0.isBitmapSubtitle } ?? matching.first
    }

    /// True when this media has subtitles in `language` but every one of them is a bitmap.
    ///
    /// The signal for fetching a text subtitle instead: it honours the font settings, and it is the
    /// only kind `SubtitleRetimer` can correct. Distinct from having no track at all, which already
    /// has its own fallback.
    func hasOnlyBitmapSubtitles(forLanguage language: String) -> Bool {
        let matching = filter { $0.kind == .subtitle && $0.matchesLanguage(language) }
        return !matching.isEmpty && matching.allSatisfy(\.isBitmapSubtitle)
    }
}
