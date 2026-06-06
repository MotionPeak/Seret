import DebridCore
import DebridUI
import SwiftUI

/// The player's settings sheet (presented from the transport): audio tracks, subtitles
/// (existing tracks + on-demand Hebrew/English download), and playback speed. Drives the
/// shared `PlayerModel`.
struct PlayerSettingsSheet: View {
    let model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Audio") {
                    if model.audioTracks.isEmpty {
                        Text("None").foregroundStyle(Theme.Palette.textSecondary)
                    }
                    ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                        Button(entry.label) { model.selectAudio(id: entry.track.id); dismiss() }
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .listRowBackground(Theme.Palette.surface1)

                Section("Subtitles") {
                    Button("Off") { model.selectSubtitleOff(); dismiss() }
                        .foregroundStyle(Theme.Palette.textPrimary)
                    ForEach(labeled(model.subtitleTracks), id: \.track.id) { entry in
                        Button(entry.label) { model.selectSubtitle(id: entry.track.id); dismiss() }
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    ForEach(model.subtitleRows) { row in downloadRow(row) }
                }
                .listRowBackground(Theme.Palette.surface1)

                Section("Playback Speed") {
                    ForEach(speeds, id: \.value) { opt in
                        Button {
                            model.setPlaybackSpeed(opt.value)
                        } label: {
                            HStack {
                                Text(opt.label)
                                Spacer()
                                if model.playbackSpeed == opt.value {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Palette.gold)
                                }
                            }
                        }
                        .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .listRowBackground(Theme.Palette.surface1)
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .tint(Theme.Palette.gold)
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func downloadRow(_ row: PlayerModel.SubtitleRow) -> some View {
        let lang = row.language == "he" ? "Hebrew" : "English"
        Button {
            Task { await model.requestSubtitle(language: row.language) }
        } label: {
            HStack {
                Text("\(lang) (download)")
                Spacer()
                switch row.state {
                case .idle:           Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.textSecondary)
                case .downloading:    ProgressView()
                case .attached:       Image(systemName: "checkmark").foregroundStyle(Theme.Palette.gold)
                case .capReached:     Text("Daily limit").font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                case .noAccount:      Text("Add account in Settings").font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                case .error:          Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.gold)
                }
            }
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .disabled(isDisabled(row))
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

    /// De-duplicated language naming (mirrors the tvOS panel): "[German]" → "German", "German 2".
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
