import DebridCore
import DebridUI
import SwiftUI

/// The sectioned version list: everything that plays at once above everything that downloads
/// first, and inside each block the oversized releases under their own heading, then the rest.
///
/// Big releases get a section of their own because ranking them last for being oversized buried
/// them at the bottom of thirty-odd rows. The ranking never looks at availability, so on its own
/// it also buried instant releases among downloads. Neither changes the ranking: order inside
/// every part is its order, and the best instant release is still the first row.
///
/// Split out of `VersionsScreen` so `-uiPreview versions` can render it without a session or a
/// search round-trip.
struct VersionList: View {
    let groups: [VersionGroup]
    let picking: String?
    let onPick: (CachedStream) -> Void
    /// Each release's Hebrew subtitles, for its marks. The order already reflects them.
    var hebrew: (CachedStream) -> HebrewSubtitles = { _ in .none }

    var body: some View {
        // Lazy so the (often 30+) rows realise as they scroll in — building every chip and badge
        // up front made the list stutter on the old Add screen.
        LazyVStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(groups) { group in
                // A block heading only when there is another block to tell it apart from.
                if groups.count > 1 {
                    blockHeader(group.availability, first: group.id == groups.first?.id)
                }
                if !group.larger.isEmpty {
                    sectionHeader("Larger files",
                                  "Highest bitrate. Slower to start and heavier to skip.")
                    ForEach(group.larger) { row($0) }
                }
                if !group.rest.isEmpty {
                    if !group.larger.isEmpty {
                        sectionHeader("Recommended", "Sized to play smoothly on this hardware.")
                    }
                    ForEach(group.rest) { row($0) }
                }
            }
        }
    }

    /// Instant or Download: the block's own heading, a step above the size sections inside it and
    /// in the colours of the rows' cache badges.
    private func blockHeader(_ availability: VersionGroup.Availability, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Image(systemName: availability.systemImage)
                .foregroundStyle(availability == .instant ? Color.green : Theme.Palette.gold)
            VStack(alignment: .leading, spacing: 1) {
                Text(availability.title)
                Text(availability.caption).font(Theme.Typo.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .font(Theme.Typo.title())
        .padding(.top, first ? 0 : Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typo.headline())
            Text(caption).font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ stream: CachedStream) -> some View {
        let indicator = HebrewIndicator(hebrew(stream))
        return Button { onPick(stream) } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Hebrew inside the file is the one kind that is always in sync: on top, alone.
                if indicator == .inFile { HebrewBadge(.inFile) }
                HStack(spacing: Theme.Space.sm) {
                    CacheBadge(isCached: stream.isCached).fixedSize()
                    // Offered the row's whole remaining width first — otherwise the Spacer takes
                    // a share and the chips give up ones they had room for.
                    chips(stream).layoutPriority(1)
                    Spacer(minLength: 0)
                    if let size = stream.sizeBytes {
                        Text(Self.sizeGB(size)).font(Theme.Typo.caption())
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .fixedSize()
                    }
                    if picking == stream.infoHash {
                        ProgressView().tint(Theme.Palette.gold)
                    } else {
                        Image(systemName: stream.isCached ? "play.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(Theme.Palette.gold)
                    }
                }
                // Its own line: an iPhone row has no room left beside the chips, and this is the
                // one fact about a version that must never be truncated away.
                if indicator == .matched { HebrewBadge(.matched) }
                // The full release name — read the source (CAM/TELESYNC), year, group to confirm
                // it's the right film/version.
                Text(stream.rawTitle)
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(Theme.Space.md)
            .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// As many whole chips as fit on the line, dropping the least telling first: languages, then
    /// the year, then the codecs. Squeezed below its text's width a chip broke mid-word
    /// ("REMU/X"), and a Download badge is wider than an Instant one. The full release name is on
    /// the line below whatever is dropped here.
    private func chips(_ stream: CachedStream) -> some View {
        let parsed = stream.parsed
        let quality = [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec]
            .compactMap { $0 }
        let year = parsed.year.map { [String($0)] } ?? []
        let languages = stream.languages.prefix(2).map { $0.uppercased() }
        return ViewThatFits(in: .horizontal) {
            chipLine(year + quality + languages)
            chipLine(year + quality)
            chipLine(quality)
            chipLine(Array(quality.prefix(2)))
            chipLine(Array(quality.prefix(1)))
        }
    }

    private func chipLine(_ texts: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(texts.enumerated()), id: \.offset) { QualityChip(text: $0.element).fixedSize() }
        }
    }

    static func sizeGB(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
