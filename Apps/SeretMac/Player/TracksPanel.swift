import DebridUI
import SwiftUI

/// The right-side Audio & Subtitles panel — spec §7.4's home for it. An in-window glass panel
/// rather than an `NSMenu`/popover: a menu is a separate window the screenshot harness cannot see,
/// and M4 adds the one-tap language rows, the search browser and Timing to this same panel.
struct TracksPanel: View {
    let model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    audioSection
                    subtitleSection
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .frame(width: PlayerHUDMetrics.tracksPanelWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PlayerHUDMetrics.panelCorner, style: .continuous))
    }

    /// Measured (colour-swatch markers, step by step): a trailing sibling placed via `Spacer()`,
    /// `.overlay(alignment: .trailing)`, `ZStack(alignment: .trailing)`, a `GeometryReader`-measured
    /// `.position()`, or a leading `Text` grown via `.frame(maxWidth: .infinity)` never drew in this
    /// panel — only a plain LEADING sibling at a small fixed width did. Root cause not pinned down;
    /// every "icon on the right" here is a small fixed-width leading column instead, so the panel is
    /// at least honest about what it can show rather than silently losing the selection indicator.
    private static let rowTextWidth: CGFloat = 130

    private var header: some View {
        HStack {
            Text("Audio & Subtitles")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(width: Self.rowTextWidth + 40, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("AUDIO")
            ForEach(model.audioTracks) { track in
                row(title: track.name, isSelected: track.id == model.selectedAudioID) {
                    model.selectAudio(id: track.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("SUBTITLES")
            row(title: "Off", isSelected: model.selectedSubtitleID == nil) {
                model.selectSubtitleOff()
            }
            if !model.embeddedTracks.isEmpty {
                sectionLabel("IN THIS FILE").padding(.top, 6)
                ForEach(model.embeddedTracks) { track in
                    row(title: track.name, isSelected: track.id == model.selectedSubtitleID) {
                        model.selectSubtitle(id: track.id)
                    }
                }
            }
            if !model.downloadedTracks.isEmpty {
                sectionLabel("DOWNLOADED").padding(.top, 6)
                ForEach(model.downloadedTracks) { track in
                    row(title: model.downloadedLanguageName(forTrackID: track.id) ?? track.name,
                        isSelected: track.id == model.selectedSubtitleID) {
                        model.selectSubtitle(id: track.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.label())
            .tracking(1.5)
            .foregroundStyle(Theme.Palette.gold)
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: Self.rowTextWidth, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
                    .frame(width: 24, height: 24)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
