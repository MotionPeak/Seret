import DebridCore
import DebridUI
import SwiftUI

/// The player's playback sheet: audio, subtitles (existing + on-demand he/en), and speed —
/// each laid out as wrapping Gold Glass chips (selected = gold), not a vertical list.
struct PlayerSettingsSheet: View {
    let model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    section("Audio", "speaker.wave.2.fill") {
                        if model.audioTracks.isEmpty {
                            Text("No alternate tracks")
                                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                        } else {
                            FlowLayout {
                                ForEach(labeled(model.audioTracks), id: \.track.id) { e in
                                    chip(e.label, selected: model.selectedAudioID == e.track.id) {
                                        model.selectAudio(id: e.track.id)
                                    }
                                }
                            }
                        }
                    }

                    section("Subtitles", "captions.bubble.fill") {
                        FlowLayout {
                            chip("Off", selected: model.selectedSubtitleID == nil) { model.selectSubtitleOff() }
                            ForEach(labeled(model.subtitleTracks), id: \.track.id) { e in
                                chip(e.label, selected: model.selectedSubtitleID == e.track.id) {
                                    model.selectSubtitle(id: e.track.id)
                                }
                            }
                            ForEach(model.subtitleRows) { row in downloadChip(row) }
                        }
                    }

                    section("Speed", "speedometer") {
                        FlowLayout {
                            ForEach(speeds, id: \.value) { opt in
                                chip(opt.label, selected: model.playbackSpeed == opt.value) {
                                    model.setPlaybackSpeed(opt.value)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.canvas)
        .tint(Theme.Palette.gold)
    }

    @ViewBuilder private func section<C: View>(_ title: String, _ icon: String,
                                              @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label(title, systemImage: icon)
                .font(Theme.Typo.label()).tracking(1).foregroundStyle(Theme.Palette.gold)
            content()
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(selected ? Color(hex: 0x1A1400) : Theme.Palette.textPrimary)
            .padding(.vertical, 9).padding(.horizontal, 15)
            .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                 : AnyShapeStyle(Theme.Palette.surface2), in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func downloadChip(_ row: PlayerModel.SubtitleRow) -> some View {
        let lang = row.language == "he" ? "Hebrew" : "English"
        Button {
            Task { await model.requestSubtitle(language: row.language) }
        } label: {
            HStack(spacing: 6) {
                downloadGlyph(row.state)
                Text(lang).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 9).padding(.horizontal, 15)
            .background(Theme.Palette.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.gold.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled(row))
    }

    @ViewBuilder private func downloadGlyph(_ state: PlayerModel.SubtitleRowState) -> some View {
        switch state {
        case .idle:        Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.gold)
        case .downloading: ProgressView().controlSize(.mini)
        case .attached:    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.gold)
        case .capReached:  Image(systemName: "clock").foregroundStyle(Theme.Palette.textSecondary)
        case .noAccount:   Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(Theme.Palette.textSecondary)
        case .error:       Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.gold)
        }
    }

    private func isDisabled(_ row: PlayerModel.SubtitleRow) -> Bool {
        switch row.state {
        case .capReached, .noAccount, .downloading: return true
        default: return false
        }
    }

    private var speeds: [(label: String, value: Double)] {
        [("0.5×", 0.5), ("0.75×", 0.75), ("Normal", 1.0), ("1.25×", 1.25), ("1.5×", 1.5)]
    }

    /// De-duplicated language naming: "[German]" → "German", "German 2".
    private func labeled(_ tracks: [MediaTrack]) -> [(track: MediaTrack, label: String)] {
        let totals = Dictionary(grouping: tracks, by: { language($0) }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return tracks.map { t in
            let lang = language(t)
            seen[lang, default: 0] += 1
            let label = (totals[lang] ?? 1) > 1 ? "\(lang) \(seen[lang]!)" : lang
            return (t, label)
        }
    }

    private func language(_ track: MediaTrack) -> String {
        if let r = track.name.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            let inner = track.name[r].dropFirst().dropLast()
            if !inner.isEmpty { return String(inner) }
        }
        if let l = track.language, !l.isEmpty { return l.capitalized }
        return track.name
    }
}
