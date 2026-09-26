#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only visual harness for the Versions list, mirroring SeretTV's `-uiPreview versions`. The
/// real screen needs a signed-in session and a search round-trip; this draws the real `VersionList`
/// over fabricated releases so the Instant / Download blocks, the size sections inside them and both
/// Hebrew marks can be screenshot-verified.
///
/// The blocks are computed by `groupedByAvailability` from a ranked list exactly as in the screen,
/// so the screenshot checks the grouping as well as the layout.
///
/// Launch with `-uiPreview versions`; add `-uiPreviewAnchor bottom` to open scrolled to the end,
/// so the Download block can be screenshot without driving a swipe. Not compiled into release builds.
struct VersionsUIPreview: View {
    private static func stream(_ name: String, _ gb: Double, _ res: String,
                               _ source: String, cached: Bool, subs: [String] = [],
                               video: String? = nil, audio: String? = nil) -> CachedStream {
        CachedStream(infoHash: name, fileIdx: nil, rawTitle: name,
                     parsed: ParsedRelease(title: "Sherlock", year: 2010, resolution: res, source: source,
                                           videoCodec: video, audioCodec: audio),
                     languages: ["en"], sizeBytes: Int(gb * 1_000_000_000),
                     sourceName: "RD", isCached: cached, subtitleLanguages: subs)
    }

    private static let all: [CachedStream] = [
        stream("Sherlock.2160p.REMUX.HDR", 78, "2160p", "REMUX", cached: true),
        stream("Sherlock.2160p.REMUX.SDR", 64, "2160p", "REMUX", cached: false,
               video: "HEVC", audio: "TrueHD"),
        stream("Sherlock.2160p.BluRay.x265", 41, "2160p", "BluRay", cached: true),
        stream("Sherlock.2160p.WEB-DL.x265", 22, "2160p", "WEB-DL", cached: true,
               video: "x265", audio: "DDP5.1"),
        stream("Sherlock.1080p.BluRay.x264", 12, "1080p", "BluRay", cached: true),
        stream("Sherlock.2160p.WEB-DL.DV.x265", 18, "2160p", "WEB-DL", cached: false),
        stream("Sherlock.1080p.WEB-DL.x265", 6, "1080p", "WEB-DL", cached: false),
        stream("Sherlock.720p.BluRay.x264.HebSubs", 3, "720p", "BluRay", cached: true, subs: ["he"]),
    ]

    /// One release matched by a Hebrew subtitle (a download), one tagged HebSubs (instant).
    private static let evidence = SubtitleEvidenceSet.candidates(
        all, hebrewResults: [SubtitleResult(fileID: 1, language: "he", release: "Sherlock.1080p.WEB-DL.x265")],
        originalLanguage: "en")

    var body: some View {
        let groups = Self.all.rankedFor(originalLanguage: "en", subtitles: Self.evidence)
            .groupedByAvailability(episodesInSeason: nil)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Instant versions play right away; the rest download to Real\u{2011}Debrid first.")
                        .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    VersionList(groups: groups, picking: nil, onPick: { _ in },
                                hebrew: { Self.evidence.hebrew(forVersion: $0.infoHash) })
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(UserDefaults.standard.string(forKey: "uiPreviewAnchor") == "bottom"
                                 ? .bottom : .top)
            .background(CanvasBackground())
            .navigationTitle("Sherlock")
            .navigationBarTitleDisplayMode(.inline)
        }
        // RootView sets this app-wide; the harness bypasses RootView.
        .preferredColorScheme(.dark)
    }
}
#endif
