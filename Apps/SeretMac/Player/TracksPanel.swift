import DebridCore
import DebridUI
import SwiftUI

/// What the right-side panel is showing. The subtitle browser and "Sync to a line" live in the
/// same glass panel as the tracks (spec §7.4) — one place to look, and an in-window view the
/// screenshot harness can see (a sheet or menu would be a separate window).
enum TracksPanelMode: Equatable {
    case tracks, browser, sync
}

/// The right-side Audio & Subtitles panel: audio tracks (duplicate languages numbered); subtitles
/// Off / In this file / Downloaded; one-click Hebrew / English; Search subtitles…; Timing (sync
/// automatically, sync to a line, ±0.5 s, reset, 25 fps drift fix); speed; volume.
struct TracksPanel: View {
    let model: PlayerModel
    @Binding var mode: TracksPanelMode
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch mode {
            case .tracks:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        audioSection
                        subtitleSection
                        timingSection
                        speedSection
                        volumeSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            case .browser:
                SubtitleBrowserPanel(model: model, onPicked: { mode = .tracks })
            case .sync:
                ManualSyncPanel(model: model)
            }
        }
        .padding(20)
        .frame(width: PlayerHUDMetrics.tracksPanelWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PlayerHUDMetrics.panelCorner, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if mode != .tracks {
                Button {
                    if mode == .sync { model.endManualSync() }
                    mode = .tracks
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Back")
            }
            Text(title)
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                if mode == .sync { model.endManualSync() }
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }

    private var title: String {
        switch mode {
        case .tracks: "Audio & Subtitles"
        case .browser: "Search Subtitles"
        case .sync: "Sync to a Line"
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        section("AUDIO") {
            if model.audioTracks.isEmpty {
                Text("No alternate tracks")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                    row(title: entry.label, detail: detail(entry.track),
                        isSelected: entry.track.id == model.selectedAudioID) {
                        model.selectAudio(id: entry.track.id)
                    }
                }
            }
        }
    }

    // MARK: - Subtitles

    private var subtitleSection: some View {
        section("SUBTITLES") {
            row(title: "Off", isSelected: model.selectedSubtitleID == nil) {
                model.selectSubtitleOff()
            }
            if !model.embeddedTracks.isEmpty {
                groupCaption("IN THIS FILE")
                ForEach(labeled(model.embeddedTracks), id: \.track.id) { entry in
                    row(title: entry.label, detail: detail(entry.track),
                        isSelected: entry.track.id == model.selectedSubtitleID) {
                        model.selectSubtitle(id: entry.track.id)
                    }
                }
            }
            if !model.downloadedTracks.isEmpty {
                groupCaption("DOWNLOADED")
                ForEach(labeled(model.downloadedTracks), id: \.track.id) { entry in
                    row(title: entry.label, isSelected: entry.track.id == model.selectedSubtitleID) {
                        model.selectSubtitle(id: entry.track.id)
                    }
                }
            }
            FlowLayout {
                // One click for the common case. Hidden once attached: it then shows above.
                ForEach(model.subtitleRows) { subtitleRow in
                    if model.attachedTrackID(subtitleRow) == nil { quickChip(subtitleRow) }
                }
                chip("Search subtitles…", systemImage: "magnifyingglass") { mode = .browser }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private func quickChip(_ subtitleRow: PlayerModel.SubtitleRow) -> some View {
        let language = subtitleRow.language == "he" ? "Hebrew" : "English"
        Button {
            Task { await model.requestSubtitle(language: subtitleRow.language) }
        } label: {
            HStack(spacing: 6) {
                QuickSubtitleGlyph(state: subtitleRow.state)
                Text(language).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 6).padding(.horizontal, 11)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.gold.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .disabled(QuickSubtitleGlyph.isDisabled(subtitleRow.state))
        .help(QuickSubtitleGlyph.help(subtitleRow.state, language: language))
    }

    // MARK: - Timing

    private var timingSection: some View {
        section(timingTitle) {
            FlowLayout {
                if model.canAutoSyncSubtitle {
                    chip(autoSyncTitle, systemImage: "waveform", selected: model.autoSyncState == .synced) {
                        model.startAutoSync()
                    }
                    .disabled(model.autoSyncState == .measuring)
                }
                if model.canManualSync {
                    chip("Sync to a line…", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        model.beginManualSync()
                        mode = .sync
                    }
                }
                chip("−0.5 s") { model.adjustSubtitleDelay(by: -0.5) }
                chip("+0.5 s") { model.adjustSubtitleDelay(by: 0.5) }
                chip("Reset") { model.resetSubtitleDelay() }
                chip("25 fps (PAL)", selected: model.isCorrectingSubtitleDrift) {
                    model.setSubtitleSourceFPS(model.isCorrectingSubtitleDrift ? nil : 25)
                }
                .help("Subtitle is 25 fps (PAL) — fix drift")
            }
        }
    }

    /// The section title doubles as its readout: whether the subtitle was rate-corrected on the way
    /// in, the PAL correction, and any offset dialled on top.
    private var timingTitle: String {
        var parts = ["TIMING"]
        if model.subtitleRetimeFactor != nil { parts.append("RATE-CORRECTED") }
        if model.isCorrectingSubtitleDrift {
            parts.append(String(format: "PAL %+.0fS", model.subtitleDriftDelay))
        }
        if model.subtitleDelay != 0 { parts.append(String(format: "%+.1fS", model.subtitleDelay)) }
        return parts.joined(separator: " · ")
    }

    private var autoSyncTitle: String {
        switch model.autoSyncState {
        case .idle: "Sync automatically"
        case .measuring: "Listening…"
        case .synced: "Synced"
        case .failed: "Couldn't match audio"
        }
    }

    // MARK: - Speed and volume

    private var speedSection: some View {
        section("SPEED") {
            FlowLayout {
                ForEach(PlaybackSpeeds.all, id: \.self) { rate in
                    chip(PlaybackSpeeds.label(rate), selected: abs(model.playbackSpeed - rate) < 0.001) {
                        model.setPlaybackSpeed(rate)
                    }
                }
            }
        }
    }

    private var volumeSection: some View {
        section("VOLUME") {
            FlowLayout {
                ForEach([100, 125, 150, 175, 200], id: \.self) { percent in
                    chip("\(percent)%", selected: model.volumePercent == percent) {
                        model.setVolume(percent)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func labeled(_ tracks: [MediaTrack]) -> [(track: MediaTrack, label: String)] {
        TrackLabels.labeled(tracks) { track in
            TrackLabels.language(of: track,
                                 downloadedLanguage: model.downloadedLanguageName(forTrackID: track.id))
        }
    }

    /// The raw track name under its friendly label, when it says something the label doesn't.
    private func detail(_ track: MediaTrack) -> String? {
        let label = TrackLabels.language(of: track, downloadedLanguage: nil)
        return track.name == label ? nil : track.name
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
                .lineLimit(1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).tracking(1)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.top, 4)
    }

    private func row(title: String, detail: String? = nil, isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(detail ?? title)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.gold)
                    .frame(width: 24, height: 24)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, systemImage: String? = nil, selected: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.Palette.onGold : Theme.Palette.textPrimary)
            .padding(.vertical, 6).padding(.horizontal, 11)
            .background(selected ? AnyShapeStyle(Theme.Palette.goldGradient)
                                 : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// The one-click Hebrew/English chip's leading glyph, and when it can't be clicked.
struct QuickSubtitleGlyph: View {
    let state: PlayerModel.SubtitleRowState

    var body: some View {
        switch state {
        case .idle: Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.gold)
        case .downloading: ProgressView().controlSize(.mini)
        case .attached: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.gold)
        case .capReached: Image(systemName: "clock").foregroundStyle(Theme.Palette.textSecondary)
        case .noAccount: Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(Theme.Palette.textSecondary)
        case .error: Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.gold)
        }
    }

    static func isDisabled(_ state: PlayerModel.SubtitleRowState) -> Bool {
        switch state {
        case .capReached, .noAccount, .downloading: true
        default: false
        }
    }

    static func help(_ state: PlayerModel.SubtitleRowState, language: String) -> String {
        switch state {
        case .idle: "Download \(language) subtitles"
        case .downloading: "Downloading…"
        case .attached: "Attached"
        case .capReached: "Today's OpenSubtitles download limit is reached"
        case .noAccount: "Sign in to OpenSubtitles in Settings"
        case .error: "Couldn't get \(language) subtitles — click to try again"
        }
    }
}
