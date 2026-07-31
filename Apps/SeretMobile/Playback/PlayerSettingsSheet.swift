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
                            // Muxed tracks shipped inside the file.
                            ForEach(labeled(model.embeddedTracks), id: \.track.id) { e in
                                chip(e.label, selected: model.selectedSubtitleID == e.track.id) {
                                    model.selectSubtitle(id: e.track.id)
                                }
                            }
                            // Attached from a download this session (auto he/en or a browser pick).
                            ForEach(labeled(model.downloadedTracks), id: \.track.id) { e in
                                chip(e.label, selected: model.selectedSubtitleID == e.track.id) {
                                    model.selectSubtitle(id: e.track.id)
                                }
                            }
                            // One-click he/en for the common case (no muxed subs). Hidden once the
                            // track is attached, since it then appears as a real track above.
                            ForEach(model.subtitleRows) { row in
                                if model.attachedTrackID(row) == nil { quickChip(row) }
                            }
                            searchChip
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

                    section("Volume", "speaker.wave.3.fill") {
                        FlowLayout {
                            ForEach(volumes, id: \.self) { pct in
                                chip("\(pct)%", selected: model.volumePercent == pct) {
                                    model.setVolume(pct)
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

    /// One-tap Hebrew/English download. Dashed border marks it as an action rather than a track.
    @ViewBuilder private func quickChip(_ row: PlayerModel.SubtitleRow) -> some View {
        let language = row.language == "he" ? "Hebrew" : "English"
        Button {
            Task { await model.requestSubtitle(language: row.language) }
        } label: {
            HStack(spacing: 6) {
                downloadGlyph(row.state)
                Text(language).font(.system(size: 14, weight: .semibold))
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

    /// Opens the full ranked subtitle browser — for picking a specific release.
    private var searchChip: some View {
        NavigationLink { MobileSubtitleBrowser(model: model) } label: {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .bold))
                Text("Search subtitles…").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 9).padding(.horizontal, 15)
            .background(Theme.Palette.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var speeds: [(label: String, value: Double)] {
        [("0.5×", 0.5), ("0.75×", 0.75), ("Normal", 1.0), ("1.25×", 1.25), ("1.5×", 1.5)]
    }

    /// 100 = unity; up to 200 = VLC-style boost for quiet mixes.
    private var volumes: [Int] { [100, 125, 150, 175, 200] }

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

/// The subtitle browser on iPhone/iPad. Same model and ranking as tvOS; a plain `List` instead of
/// a focus-driven layout. Pushed inside the sheet's `NavigationStack`.
struct MobileSubtitleBrowser: View {
    @Bindable var model: PlayerModel
    @State private var languages: [SubtitleLanguage] = SubtitleLanguages.fallback
    @Environment(\.dismiss) private var dismiss

    private let pinned = ["he", "en"]

    var body: some View {
        List {
            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(SubtitleLanguages.order(languages, pinned: pinned)) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .pickerStyle(.menu)
            }
            switch model.subtitleSearchState {
            case .idle, .searching:
                HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
            case .failed:
                Text("Couldn't search subtitles. Check the OpenSubtitles account in Settings.")
                    .foregroundStyle(.secondary)
            case .loaded where model.subtitleSearchResults.isEmpty:
                Text("No subtitles found in this language.").foregroundStyle(.secondary)
            case .loaded:
                ForEach(model.subtitleSearchResults, id: \.result.fileID) { ranked in
                    Button {
                        Task { await model.useSubtitle(ranked); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(badgeText(ranked.quality))
                                    .font(.caption2.weight(.semibold))
                                Spacer()
                                if let downloads = ranked.result.downloadCount {
                                    Text(downloads.formatted(.number))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(ranked.result.release ?? ranked.result.fileName ?? "Subtitle")
                                .font(.footnote.monospaced()).lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Subtitles")
        .task {
            if let fetched = try? await SubtitleLanguages.fetch(apiKey: Secrets.openSubtitlesAPIKey),
               !fetched.isEmpty { languages = fetched }
            if model.subtitleSearchState == .idle {
                await model.searchSubtitles(language: pinned[0])
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(get: { model.subtitleSearchLanguage ?? pinned[0] },
                set: { code in Task { await model.searchSubtitles(language: code) } })
    }

    private func badgeText(_ quality: SubtitleMatch.Quality) -> String {
        switch quality {
        case .perfect:   "✓ Perfect match"
        case .good:      "Same release group"
        case .uncertain: "Different source"
        }
    }
}
