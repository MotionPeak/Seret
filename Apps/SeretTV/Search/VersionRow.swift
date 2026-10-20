import DebridCore
import DebridUI
import SwiftUI

/// One release in a versions list: cache badge, year, quality chips, languages, size, and the
/// play/download affordance. Shared by the Add screen's inline "Show all versions" list and the
/// full-screen `VersionsScreen`, so both read identically.
struct VersionRow: View {
    let stream: CachedStream
    /// True while this row's pick is being resolved (instant-add probe / download start).
    let isPicking: Bool
    /// Hebrew subtitles for this release — the first thing this household asks of a version. A
    /// track inside the file gets a line of its own at the top of the row, since it is the one
    /// kind that is always in sync; Matched sits right after the cache mark.
    var hebrew: HebrewSubtitles = .none
    let action: () -> Void

    var body: some View {
        let indicator = HebrewIndicator(hebrew)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if indicator == .inFile {
                    HebrewBadge(.inFile).padding(.bottom, 4)
                }
                HStack(spacing: 16) {
                    CacheBadge(isCached: stream.isCached).fixedSize()
                    if indicator == .matched { HebrewBadge(.matched).fixedSize() }
                    // Offered the row's whole remaining width first — otherwise the Spacer takes a
                    // share and the chips give up ones they had room for.
                    chips.layoutPriority(1)
                    Spacer(minLength: 0)
                    if let size = stream.sizeBytes {
                        Text(Self.sizeGB(size)).font(.seretCallout)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize()
                    }
                    if isPicking {
                        ProgressView()
                    } else {
                        Image(systemName: stream.isCached ? "play.circle" : "icloud.and.arrow.down")
                    }
                }
                Text(stream.rawTitle).font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .buttonStyle(SeretRowStyle())
    }

    /// As many whole chips as fit, dropping languages first, then the year. Squeezed below their
    /// text's width, chips — and the Hebrew pill beside them — broke mid-word ("REMU/X",
    /// "Hebrew · / Matched") on releases that list four audio languages. The full release name is
    /// on the line below whatever is dropped here.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            chipLine(languages: 4, year: true)
            chipLine(languages: 2, year: true)
            chipLine(languages: 0, year: true)
            chipLine(languages: 0, year: false)
        }
    }

    private func chipLine(languages: Int, year: Bool) -> some View {
        HStack(spacing: 16) {
            if year, let year = stream.parsed.year {
                Text(String(year)).font(.seret(.caption1, .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.Palette.glassFaint, in: Capsule())
            }
            QualityChips(parsed: stream.parsed)
            if languages > 0 { LanguageBadges(codes: Array(stream.languages.prefix(languages))) }
        }
    }

    static func sizeGB(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

/// ⚡ Instant (already on RD) vs ☁︎ Download (will fetch) — from Comet's cache marker.
///
/// Neutral on purpose: white is the TV's only accent. Instant is white on glass; Download is
/// secondary grey on a fainter fill, with the cloud symbol saying "fetched first".
struct CacheBadge: View {
    let isCached: Bool

    /// The badge's symbol — also the Instant / Download block headings'.
    static func symbol(cached: Bool) -> String { cached ? "bolt.fill" : "icloud.and.arrow.down" }

    var body: some View {
        Label(isCached ? "Instant" : "Download", systemImage: Self.symbol(cached: isCached))
            .font(.seret(.caption1, .bold))
            .foregroundStyle(isCached ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            .padding(.vertical, 4).padding(.horizontal, 10)
            .background(isCached ? Theme.Palette.glass : Theme.Palette.glassFaint, in: Capsule())
    }
}

/// Uppercased ISO-639-1 language chips (e.g. EN · FR).
struct LanguageBadges: View {
    let codes: [String]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(codes.prefix(4), id: \.self) { code in
                Text(code.uppercased())
                    .font(.seret(.caption1, .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.Palette.glassFaint, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
            }
        }
    }
}
