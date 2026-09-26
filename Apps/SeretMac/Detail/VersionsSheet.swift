import DebridCore
import DebridUI
import SwiftUI

/// The Versions sheet's content: every cached and uncached release, ranked, with an instant pick
/// playing right away and anything else becoming a tracked download shown in place.
///
/// A standalone view over an explicit `VersionsModel` (Decision 7 — a sheet's dependencies are
/// passed in, never read from `@Environment`, since a non-optional Observable read traps across a
/// presentation boundary), so the `-uiPreview` harness can render it inline as well as `TitlePage`
/// presenting it as a real `.sheet`.
struct VersionsSheet: View {
    let model: VersionsModel
    /// A pick that turned out instantly playable. The caller dismisses, presents playback and
    /// shows the "Added to Real‑Debrid" toast — this view only reports the outcome.
    let onPlay: (PlaybackRequest) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Text("Instant versions play right away; the rest download to Real\u{2011}Debrid first.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            if let localError {
                Label(localError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            downloadStatus
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
            }
        }
        .padding(24)
        .frame(width: 680, height: 560, alignment: .topLeading)
        .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task { await model.load() }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack {
            Text("Versions \u{00B7} \(model.title)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        if let status = model.downloadStatus {
            switch status.phase {
            case .queued:
                Label("Starting download\u{2026}", systemImage: "arrow.down.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.Palette.gold)
            case .downloading:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading \(Int(status.fraction * 100))% to Real\u{2011}Debrid\u{2026}")
                        .font(.system(size: 13)).foregroundStyle(Theme.Palette.gold)
                    GoldProgressBar(fraction: status.fraction)
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13)).foregroundStyle(.orange)
            case .ready:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ForEach(0..<6, id: \.self) { _ in
                ShimmerView(cornerRadius: 10).frame(height: 56)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label("Couldn\u{2019}t load versions. Check your connection and try again.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                Button("Try Again") { Task { await model.load() } }
                    .buttonStyle(GlassButtonStyle())
            }
        case .empty:
            Text("No other versions found.")
                .font(.system(size: 13)).foregroundStyle(Theme.Palette.textSecondary)
        case .ready:
            ForEach(model.groups) { group in
                // A block heading only when there is another block to tell it apart from.
                if model.groups.count > 1 {
                    blockHeader(group.availability, first: group.id == model.groups.first?.id)
                }
                if !group.larger.isEmpty {
                    sectionHeader("LARGER FILES")
                    ForEach(group.larger) { row($0) }
                }
                if !group.rest.isEmpty {
                    sectionHeader("RECOMMENDED")
                    ForEach(group.rest) { row($0) }
                }
            }
        }
    }

    /// Instant or Download: the block's own heading, a step above the size sections inside it and
    /// in the colours of the rows' cache badges. The ranking never looks at availability, so
    /// without the blocks a release that plays at once sat among ones that must download first.
    private func blockHeader(_ availability: VersionGroup.Availability, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: availability.systemImage)
                .foregroundStyle(availability == .instant ? Theme.Palette.gold : Theme.Palette.textPrimary)
            Text(availability.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(availability.caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .font(.system(size: 15, weight: .bold))
        .padding(.top, first ? 0 : 14)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.Palette.gold)
            .padding(.top, 4)
    }

    private func row(_ stream: CachedStream) -> some View {
        let hebrew = HebrewIndicator(model.hebrew(for: stream))
        return Button { pick(stream) } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Hebrew inside the file is the one kind that is always in sync: on top, alone.
                if hebrew == .inFile { HebrewBadge(.inFile) }
                HStack(alignment: .top, spacing: 12) {
                    // Pinned: the chips beside them take the row's width first, and a long release
                    // name must truncate rather than squeeze the badge or the size to "…".
                    badge(stream.isCached).fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        chipLine(stream, matched: hebrew == .matched)
                        Text(stream.rawTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    // Offered the row's width before the Spacer, so the chips never give up ones
                    // they had room for.
                    .layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing(stream).fixedSize()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(stream.isCached ? "Play Now" : "Download") { pick(stream) }
        }
    }

    /// The Matched pill, then as many whole chips as fit: languages go first, then the codecs. The
    /// pill is never dropped. Squeezed below its text's width a chip broke mid-word ("REMU/X").
    private func chipLine(_ stream: CachedStream, matched: Bool) -> some View {
        let chips = VersionText.chips(stream.parsed)
        let languages = VersionText.languages(stream.languages)
        return ViewThatFits(in: .horizontal) {
            chipRow(chips, languages: languages, matched: matched)
            chipRow(chips, languages: nil, matched: matched)
            chipRow(Array(chips.prefix(2)), languages: nil, matched: matched)
        }
    }

    private func chipRow(_ chips: [String], languages: String?, matched: Bool) -> some View {
        HStack(spacing: 6) {
            if matched { HebrewBadge(.matched) }
            ForEach(chips, id: \.self) { QualityChip(text: $0).fixedSize() }
            if let languages {
                Text(languages).font(.system(size: 11)).foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private func badge(_ isCached: Bool) -> some View {
        let label = Label(isCached ? "Instant" : "Download",
                          systemImage: isCached ? "bolt.fill" : "arrow.down.circle")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
        if isCached {
            label.foregroundStyle(Theme.Palette.onGold)
                .background(Theme.Palette.goldGradient, in: Capsule())
        } else {
            label.foregroundStyle(Theme.Palette.textPrimary)
                .glassEffect(.regular, in: Capsule())
        }
    }

    @ViewBuilder private func trailing(_ stream: CachedStream) -> some View {
        if model.picking == stream.infoHash {
            Label {
                Text("Starting\u{2026}").font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: "ellipsis").symbolEffect(.pulse, isActive: !reduceMotion)
            }
            .foregroundStyle(Theme.Palette.gold)
        } else if let size = VersionText.size(stream.sizeBytes) {
            Text(size).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func pick(_ stream: CachedStream) {
        guard model.picking == nil else { return }
        localError = nil
        Task {
            switch await model.pick(stream) {
            case let .play(request):
                onPlay(request)
            case .failed(let message) where !message.isEmpty:
                localError = message
            default:
                break   // downloadStarted — `downloadStatus` reflects it; busy pick — ignored
            }
        }
    }
}
