import SwiftUI
import DebridUI
import DebridCore

/// Which list the settings sheet shows. Chosen from the player's control row.
enum SettingsSection {
    case subtitles, audio, speed

    var title: String {
        switch self {
        case .subtitles: "Subtitles"
        case .audio:     "Audio"
        case .speed:     "Speed"
        }
    }
}

/// The player settings as a right-hand side sheet: one list — Subtitles, Audio or Speed — opened
/// at the section the viewer picked in the control row. Its behaviour (tracks, on-demand
/// subtitles, search, sync, delay, speed) is exactly that of the three-column panel it replaced;
/// only the presentation moved.
struct SettingsPanel: View {
    @Bindable var model: PlayerModel
    let initialSection: SettingsSection
    /// Leave the sheet and open the full subtitle browser.
    let onSearchSubtitles: () -> Void
    /// Leave the sheet and open the sync-to-a-line pad, so the picture is visible while you dial.
    let onSyncToLine: () -> Void
    let onClose: () -> Void

    static let width: CGFloat = 640
    private static let corner: CGFloat = 32
    /// The sheet's distance from the screen's top, right and bottom edges.
    private static let inset: CGFloat = 24

    var body: some View {
        PlaybackSettingsList(model: model, section: initialSection,
                             onSearchSubtitles: onSearchSubtitles,
                             onSyncToLine: onSyncToLine, onPick: onClose)
            .padding(.top, 64)
            .padding(.horizontal, 34)
            .padding(.bottom, 34)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                LinearGradient(colors: [Theme.Palette.panelTop, Theme.Palette.panelBottom],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .padding(Self.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            // Measured from the screen's edges, not the overscan-safe area: the sheet is a surface,
            // and its own 34pt gutter keeps the rows' text inside title-safe.
            .ignoresSafeArea()
    }
}

// MARK: - The sheet's list

private struct PlaybackSettingsList: View {
    @Bindable var model: PlayerModel
    let section: SettingsSection
    let onSearchSubtitles: () -> Void
    let onSyncToLine: () -> Void
    let onPick: () -> Void
    /// Seeds focus to what is ON when the sheet opens — the subtitle playing ("Off" only when none
    /// is), the audio track, the speed — so the arrows navigate the options immediately, with no
    /// extra click to "enter" the list.
    ///
    /// Subtitles always used to land on "Off", which made Select the most destructive press in the
    /// panel: the viewer who opened it by accident and clicked to get back to the film switched
    /// their subtitles off. The current choice is also where every other player puts you.
    ///
    /// `@FocusState` + `.onAppear` is the reliable seed HERE; `.defaultFocus`/`.focusScope` stranded
    /// focus and left the panel uncontrollable. (The opposite holds for the Detail screen's
    /// off-screen CTA, which NEEDS `.defaultFocus` — don't generalize either rule.)
    @FocusState private var landing: Landing?

    private enum Landing: Hashable { case off, track(String), audio(String), speed(Double) }

    /// The row matching the current choice when it is on screen. A seed that matches no row is
    /// dropped, and the sheet would open with focus wherever the engine happened to put it.
    private var landingTarget: Landing? {
        switch section {
        case .subtitles:
            guard let id = model.displayedSubtitleID,
                  (model.embeddedTracks + model.downloadedTracks).contains(where: { $0.id == id })
            else { return .off }
            return .track(id)
        case .audio:
            if let id = model.displayedAudioID, model.audioTracks.contains(where: { $0.id == id }) {
                return .audio(id)
            }
            return model.audioTracks.first.map { .audio($0.id) }
        case .speed:
            let current = speedOptions.first { $0.value == model.playbackSpeed } ?? speedOptions[2]
            return .speed(current.value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(section.title)
                .font(.seret(36, .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.leading, 28)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    switch section {
                    case .subtitles: subtitleRows
                    case .audio:     audioRows
                    case .speed:     speedRows
                    }
                }
                .padding(.vertical, 2)
            }
            // tvOS scroll views draw past their bounds; a long subtitle list ran out of the sheet's
            // bottom edge. No row lifts on focus, so clipping cuts nothing that matters.
            .clipShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { landing = landingTarget }
    }

    @ViewBuilder private var audioRows: some View {
        ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
            CheckRow(title: entry.label, checked: model.displayedAudioID == entry.track.id) {
                // The sheet opens with focus ON the playing track, so the first Select often lands
                // here. Re-selecting it is not free: libvlc tears the audio decoder down and builds
                // it again, which is audible silence. A press on the track already playing does
                // nothing.
                guard model.displayedAudioID != entry.track.id else { return }
                model.selectAudio(id: entry.track.id)        // stay open — pick more / compare
            }
            .focused($landing, equals: .audio(entry.track.id))
        }
        if model.audioTracks.isEmpty {
            Text("None")
                .font(.seret(27, .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.leading, 28)
        }
    }

    private var subtitleRows: some View {
        Group {
            CheckRow(title: "Off", checked: model.displayedSubtitleID == nil) {
                guard model.displayedSubtitleID != nil else { return }   // already off
                model.selectSubtitleOff()
            }
                .focused($landing, equals: .off)

            // Muxed subtitle tracks that ship inside the file.
            if !model.embeddedTracks.isEmpty {
                groupCaption("IN THIS FILE")
                ForEach(labeled(model.embeddedTracks), id: \.track.id) { entry in
                    CheckRow(title: entry.label, checked: model.displayedSubtitleID == entry.track.id) {
                        selectSubtitle(entry.track.id)
                    }
                    .focused($landing, equals: .track(entry.track.id))
                }
            }
            // Subtitles attached from a download this session (auto he/en or a browser pick).
            if !model.downloadedTracks.isEmpty {
                groupCaption("DOWNLOADED")
                ForEach(labeled(model.downloadedTracks), id: \.track.id) { entry in
                    CheckRow(title: entry.label, checked: model.displayedSubtitleID == entry.track.id) {
                        selectSubtitle(entry.track.id)
                    }
                    .focused($landing, equals: .track(entry.track.id))
                }
            }
            // One-click Hebrew/English, for the overwhelmingly common case: an RD rip with no muxed
            // subtitles at all. Without these the column collapses to "Off" + "Search subtitles…",
            // which is what shipped and read as "no subtitle info" — the search browser is the
            // right tool for picking a specific release, not for "just give me Hebrew".
            // Shown only while NOT yet attached; once downloaded the track appears under DOWNLOADED
            // above, so listing it here too would duplicate it.
            ForEach(model.subtitleRows) { row in
                if model.attachedTrackID(row) == nil {
                    // Never `.disabled`: the row turned "downloading" — and disabled — the instant it
                    // was pressed, which threw focus to the neighbouring row (usually the English
                    // one), so the viewer's second press downloaded English. A press it cannot act
                    // on is ignored instead.
                    CheckRow(title: quickTitle(row), checked: false) {
                        guard !isDisabled(row) else { return }
                        Task { await model.requestSubtitle(language: row.language) }
                    }
                }
            }

            CheckRow(title: "Search subtitles…", checked: false) { onSearchSubtitles() }

            // The last resort when a subtitle still does not line up — and the ONLY one available
            // for a muxed track, which cannot be rewritten the way a downloaded file is.
            groupCaption(timingCaption)
            // The automatic answer, offered first because it is the one that needs no judgement.
            // Only for a subtitle we downloaded: a muxed track is timed against this exact file by
            // construction, and we hold no cue list for it to correlate.
            //
            // Pressing it closes the panel: the measurement takes minutes, and the point of it
            // running in the background is that the viewer goes back to the film. It reports from
            // the bar across the top of the picture until it is done.
            if model.canAutoSyncSubtitle {
                CheckRow(title: autoSyncTitle, checked: model.autoSyncState == .synced) {
                    model.startAutoSync()
                    onPick()
                }
                .disabled(model.autoSyncState == .measuring)
            }
            // The measurement the viewer can make that the machine cannot: they know when a line
            // was spoken. Under the automatic answer because that one needs no judgement, above
            // the ±0.5s chips because this is a measurement and those are a guess.
            if model.canManualSync {
                CheckRow(title: "Sync to a line…", checked: false) { onSyncToLine() }
            }
            CheckRow(title: "Show earlier  −0.5s", checked: false) {
                model.adjustSubtitleDelay(by: -0.5)
            }
            CheckRow(title: "Show later  +0.5s", checked: false) {
                model.adjustSubtitleDelay(by: 0.5)
            }
            // Shown unconditionally, even at zero, where it is a harmless no-op. Hiding it once the
            // offset returns to zero would destroy the row the viewer is standing on at the exact
            // moment they press it, and tvOS drops focus when the focused view goes away.
            CheckRow(title: "Reset timing", checked: false) { model.resetSubtitleDelay() }
            // The muxed-track answer. A track inside the container cannot be rewritten the way a
            // downloaded file is, and a constant offset cannot answer a rate error — but an offset
            // recomputed on every tick can, because it grows exactly as fast as the drift.
            // 25fps is the one that matters: every subtitle for a BBC show is timed to the PAL
            // master, and the encodes are 23.976.
            CheckRow(title: "Subtitle is 25fps (PAL) — fix drift",
                     checked: model.isCorrectingSubtitleDrift) {
                model.setSubtitleSourceFPS(model.isCorrectingSubtitleDrift ? nil : 25)
            }
            // A downloaded subtitle can be moved any distance (the file is rewritten); a built-in
            // one only as far as libvlc can reach, and past that every line silently vanishes.
            // Last in the group and not focusable, so appearing cannot move the row in focus.
            if model.subtitleOffsetBeyondEmbeddedReach {
                Text(PlayerModel.embeddedSubtitleReachNote)
                    .font(.seret(.caption2, .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A press on the subtitle already showing does nothing — like the audio rows, the sheet opens
    /// with focus on it, and re-selecting a track makes libvlc reload it for no change.
    private func selectSubtitle(_ id: String) {
        guard model.displayedSubtitleID != id else { return }
        model.selectSubtitle(id: id)
    }

    /// The timing group's caption doubles as its readout: whether the attached subtitle was already
    /// rate-corrected on the way in, and whatever offset has been dialled on top.
    private var timingCaption: String {
        var parts = ["TIMING"]
        if model.subtitleRetimeFactor != nil { parts.append("RATE-CORRECTED") }
        if model.isCorrectingSubtitleDrift {
            parts.append(String(format: "PAL %+.0fs", model.subtitleDriftDelay))
        }
        if model.subtitleDelay != 0 { parts.append(String(format: "%+.1fs", model.subtitleDelay)) }
        return parts.joined(separator: " · ")
    }

    /// What the auto-sync row says, which is also its only progress indicator — it listens to a
    /// few minutes of the film, so it is not instant and must not look stuck.
    private var autoSyncTitle: String {
        switch model.autoSyncState {
        case .idle:      "Sync automatically"
        case .measuring: "Listening to the film…"
        case .synced:    "Synced automatically"
        case .failed:    "Couldn't match the audio — nudge it by hand"
        }
    }

    /// Names the language and, when it matters, says why the row is not actionable.
    private func quickTitle(_ row: PlayerModel.SubtitleRow) -> String {
        let language = row.language == "he" ? "Hebrew" : "English"
        switch row.state {
        case .downloading: return "\(language) — downloading…"
        case .capReached:  return "\(language) — daily limit reached"
        case .noAccount:   return "\(language) — add an OpenSubtitles account"
        case .error:       return "\(language) — not found, try Search"
        default:           return "\(language) (download)"
        }
    }

    private func isDisabled(_ row: PlayerModel.SubtitleRow) -> Bool {
        switch row.state {
        case .capReached, .noAccount, .downloading: return true
        default: return false
        }
    }

    /// A small sub-header separating muxed tracks from ones downloaded this session.
    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.seret(.caption2, .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.top, 18).padding(.bottom, 4)
            .padding(.leading, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedRows: some View {
        ForEach(speedOptions, id: \.value) { opt in
            CheckRow(title: opt.label, checked: model.playbackSpeed == opt.value) {
                model.setPlaybackSpeed(opt.value)
            }
            .focused($landing, equals: .speed(opt.value))
        }
    }

    private var speedOptions: [(label: String, value: Double)] {
        [("0.5x", 0.5), ("0.75x", 0.75), ("Normal", 1.0), ("1.25x", 1.25), ("1.5x", 1.5)]
    }

    /// Same de-duplicated language naming as before.
    private func labeled(_ tracks: [MediaTrack]) -> [(track: MediaTrack, label: String)] {
        let totals = Dictionary(grouping: tracks, by: { language($0) }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return tracks.map { track in
            let lang = language(track)
            seen[lang, default: 0] += 1
            let label = (totals[lang] ?? 1) > 1 ? "\(lang) \(seen[lang]!)" : lang
            return (track, label)
        }
    }

    private func language(_ track: MediaTrack) -> String {
        // A downloaded subtitle first: VLCKit names a slave "Track 3" and gives it no language, so
        // only the language row that owns it can say it is the Hebrew the viewer asked for.
        if let downloaded = model.downloadedLanguageName(forTrackID: track.id) { return downloaded }
        if let r = track.name.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            let inner = track.name[r].dropFirst().dropLast()
            if !inner.isEmpty { return String(inner) }
        }
        // "eng" / "he" rather than "Eng" / "He": a two-letter stub is not a language name, and
        // this row sits directly under pills that say "Hebrew" and "English" in as many words.
        if let l = track.language, !l.isEmpty { return PlayerModel.languageName(l) }
        return track.name
    }
}

// MARK: - Building blocks

/// A sheet row: 74pt tall, the label left, a ✓ right when it is the current choice. Focus fills it
/// with the white pill and turns its text dark — the ✓ follows, so the selection still reads on
/// the focused row.
private struct CheckRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.seret(27, .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .opacity(checked ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SheetRowButtonStyle())
    }
}

/// The sheet row's look: no fill at rest, the white pill with dark content on focus. No lift — a
/// scaled row would push past the sheet's edge, and the pill alone says where focus is.
private struct SheetRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused: Bool
        @Environment(\.isEnabled) private var enabled: Bool
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Theme.Palette.onFocus : Theme.Palette.textPrimary)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .background(focused ? Theme.Palette.focus : .clear, in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : (enabled ? 1 : 0.45))
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
