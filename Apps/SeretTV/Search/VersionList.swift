import DebridCore
import DebridUI
import SwiftUI

/// The sectioned version list: oversized releases first under their own heading, then the rest.
///
/// Nothing is filtered. Ranking a 70–80GB REMUX last for being oversized left it at the bottom of
/// thirty-odd rows — present, but effectively invisible, which reads as "the big ones aren't
/// there". Giving them a section of their own at the top puts them one glance away while leaving
/// the ranking, and therefore what "best" picks, exactly as it was.
///
/// Split out from `VersionsScreen` so it can be screenshot-verified with `-uiPreview versions`,
/// without a session, a search round-trip, or the focus engine.
struct VersionList: View {
    let larger: [CachedStream]
    let rest: [CachedStream]
    let picking: String?
    let onPick: (CachedStream) -> Void
    /// Each release's Hebrew subtitles, for its badge. The order already reflects them.
    var hebrew: (CachedStream) -> HebrewSubtitles = { _ in .none }

    var body: some View {
        // Lazy so the (often 30+) rows realise as they scroll in — building every chip and badge
        // up front made the list stutter.
        LazyVStack(alignment: .leading, spacing: 14) {
            if !larger.isEmpty {
                header("LARGER FILES", "Highest bitrate. Slower to start and heavier to skip.")
                ForEach(larger) { row($0) }
            }
            if !rest.isEmpty {
                // Only worth a heading when there is another section to tell it apart from.
                if !larger.isEmpty {
                    header("RECOMMENDED", "Sized to play smoothly on this hardware.")
                }
                ForEach(rest) { row($0) }
            }
        }
    }

    private func row(_ stream: CachedStream) -> some View {
        VersionRow(stream: stream, isPicking: picking == stream.infoHash, hebrew: hebrew(stream)) {
            onPick(stream)
        }
    }

    /// A group heading. Plain text, so it takes no focus and the d-pad travels straight from the
    /// last row of one section into the first of the next.
    private func header(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.seret(.caption1, .bold)).tracking(1.2)
                .foregroundStyle(Theme.Palette.gold)
            Text(caption).font(.seretCaption2)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
