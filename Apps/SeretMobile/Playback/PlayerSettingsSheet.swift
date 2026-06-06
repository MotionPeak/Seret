import DebridCore
import DebridUI
import SwiftUI

/// The player's playback sheet: audio tracks, subtitles (existing + on-demand he/en download),
/// and speed — grouped Gold Glass cards with a gold check on the current selection.
struct PlayerSettingsSheet: View {
    let model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                audioSection
                subtitleSection
                speedSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .tint(Theme.Palette.gold)
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
    }

    private var audioSection: some View {
        Section {
            if model.audioTracks.isEmpty {
                Text("None").foregroundStyle(Theme.Palette.textSecondary)
            }
            ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                selectRow(entry.label, selected: model.selectedAudioID == entry.track.id) {
                    model.selectAudio(id: entry.track.id)
                }
            }
        } header: { header("Audio", "speaker.wave.2.fill") }
        .listRowBackground(Theme.Palette.surface1)
    }

    private var subtitleSection: some View {
        Section {
            selectRow("Off", selected: model.selectedSubtitleID == nil) { model.selectSubtitleOff() }
            ForEach(labeled(model.subtitleTracks), id: \.track.id) { entry in
                selectRow(entry.label, selected: model.selectedSubtitleID == entry.track.id) {
                    model.selectSubtitle(id: entry.track.id)
                }
            }
            ForEach(model.subtitleRows) { row in downloadRow(row) }
        } header: { header("Subtitles", "captions.bubble.fill") }
        .listRowBackground(Theme.Palette.surface1)
    }

    private var speedSection: some View {
        Section {
            ForEach(speeds, id: \.value) { opt in
                selectRow(opt.label, selected: model.playbackSpeed == opt.value) {
                    model.setPlaybackSpeed(opt.value)
                }
            }
        } header: { header("Speed", "speedometer") }
        .listRowBackground(Theme.Palette.surface1)
    }

    private func header(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(Theme.Typo.label()).tracking(1).foregroundStyle(Theme.Palette.gold)
    }

    private func selectRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.Palette.gold).fontWeight(.bold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func downloadRow(_ row: PlayerModel.SubtitleRow) -> some View {
        let lang = row.language == "he" ? "Hebrew" : "English"
        Button {
            Task { await model.requestSubtitle(language: row.language) }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.textSecondary)
                Text("\(lang) subtitles").foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                downloadState(row.state)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled(row))
    }

    @ViewBuilder private func downloadState(_ state: PlayerModel.SubtitleRowState) -> some View {
        switch state {
        case .idle:        EmptyView()
        case .downloading: ProgressView()
        case .attached:    Image(systemName: "checkmark").foregroundStyle(Theme.Palette.gold).fontWeight(.bold)
        case .capReached:  Text("Daily limit").font(.caption).foregroundStyle(Theme.Palette.textTertiary)
        case .noAccount:   Text("Add account in Settings").font(.caption).foregroundStyle(Theme.Palette.textTertiary)
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
