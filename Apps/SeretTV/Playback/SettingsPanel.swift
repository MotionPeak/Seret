import SwiftUI
import DebridUI
import DebridCore

/// The top-down player settings panel — just the three things you actually change mid-playback:
/// Audio Streams, Subtitles, and Playback Speed. (No Info / Technical tabs.)
struct SettingsPanel: View {
    @Bindable var model: PlayerModel
    /// Leave the panel and open the full subtitle browser (Task 9).
    let onSearchSubtitles: () -> Void
    /// Leave the panel and open the sync-to-a-line pad, so the picture is visible while you dial.
    let onSyncToLine: () -> Void
    let onClose: () -> Void

    /// The panel's own inner gutter. Deliberately NOT `Theme.Layout.contentMargin`: it is the same
    /// number today, but it means "space inside this card", not "the page's overscan-safe inset",
    /// and the two must stay free to move independently. (The margin token IS correct on the
    /// padding below the background, which positions the card on the page.)
    private static let innerGutter: CGFloat = 60

    var body: some View {
        PlaybackColumns(model: model, onSearchSubtitles: onSearchSubtitles,
                        onSyncToLine: onSyncToLine, onPick: onClose)
            .padding(.horizontal, Self.innerGutter)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Dark translucent backdrop — matches the native player.
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.Palette.canvas.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.Palette.gold.opacity(0.18), lineWidth: 1))
            )
            .padding(.horizontal, Theme.Layout.contentMargin)
            .padding(.top, 40)                // sits at the top of the screen
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Playback Settings columns

private struct PlaybackColumns: View {
    @Bindable var model: PlayerModel
    let onSearchSubtitles: () -> Void
    let onSyncToLine: () -> Void
    let onPick: () -> Void
    /// Seeds focus to the "Subtitles → Off" row when the panel opens, so the arrows navigate the
    /// options immediately — no extra click to "enter" the menu. `@FocusState` + `.onAppear` is the
    /// reliable seed HERE; `.defaultFocus`/`.focusScope` stranded focus and left the panel
    /// uncontrollable. (The opposite holds for the Detail screen's off-screen CTA, which NEEDS
    /// `.defaultFocus` — don't generalize either rule.)
    @FocusState private var landingFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            audioColumn
            subtitlesColumn
            speedColumn
        }
        .onAppear { landingFocused = true }
    }

    private var audioColumn: some View {
        SettingsColumn(header: "AUDIO STREAMS") {
            ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                CheckRow(title: entry.label, checked: model.selectedAudioID == entry.track.id) {
                    model.selectAudio(id: entry.track.id)        // stay open — pick more / compare
                }
            }
            if model.audioTracks.isEmpty {
                Text("None").font(.seretCallout).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitlesColumn: some View {
        SettingsColumn(header: "SUBTITLES") {
            CheckRow(title: "Off", checked: model.selectedSubtitleID == nil) { model.selectSubtitleOff() }
                .focused($landingFocused)         // first focused when the panel opens

            // Muxed subtitle tracks that ship inside the file.
            if !model.embeddedTracks.isEmpty {
                groupCaption("IN THIS FILE")
                ForEach(labeled(model.embeddedTracks), id: \.track.id) { entry in
                    CheckRow(title: entry.label, checked: model.selectedSubtitleID == entry.track.id) {
                        model.selectSubtitle(id: entry.track.id)
                    }
                }
            }
            // Subtitles attached from a download this session (auto he/en or a browser pick).
            if !model.downloadedTracks.isEmpty {
                groupCaption("DOWNLOADED")
                ForEach(labeled(model.downloadedTracks), id: \.track.id) { entry in
                    CheckRow(title: entry.label, checked: model.selectedSubtitleID == entry.track.id) {
                        model.selectSubtitle(id: entry.track.id)
                    }
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
                    CheckRow(title: quickTitle(row), checked: false) {
                        Task { await model.requestSubtitle(language: row.language) }
                    }
                    .disabled(isDisabled(row))
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
        }
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
            .padding(.top, 6)
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedColumn: some View {
        SettingsColumn(header: "PLAYBACK SPEED") {
            ForEach(speedOptions, id: \.value) { opt in
                CheckRow(title: opt.label, checked: model.playbackSpeed == opt.value) {
                    model.setPlaybackSpeed(opt.value)
                }
            }
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

private struct SettingsColumn<Content: View>: View {
    let header: String
    @ViewBuilder var content: Content
    /// Cap each column's height so a long track list (e.g. a REMUX with many subtitle streams)
    /// scrolls INSIDE the column instead of growing the whole panel off-screen (which pushed the
    /// tab bar out of view). tvOS auto-scrolls a `ScrollView` to keep the focused row visible.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(header).font(.seret(.caption1, .bold))
                .foregroundStyle(Theme.Palette.gold)
                .tracking(1.2)
                .padding(.leading, 30)        // align with the rows below
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.vertical, 2)
                    // The focus pill extends past the row's text and the ScrollView clips its edge —
                    // inset the rows so the pill (and its focus lift) has room and never cuts off.
                    .padding(.horizontal, 30)
            }
        }
        .frame(minWidth: 240, maxHeight: 640, alignment: .leading)
        // Each column is ONE target. The three have different lengths and independent scroll
        // offsets, so without sections a horizontal move from the bottom of the longest column
        // found no candidate beside it and died.
        .focusSection()
    }
}

/// A native-style row: a checkmark when selected + label, focus-tinted on tvOS.
private struct CheckRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.seret(.callout, .bold))
                    .foregroundStyle(Theme.Palette.gold)
                    .opacity(checked ? 1 : 0)
                Text(title).font(.seretCallout)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

/// A settings row's focus look: the same gold-glass treatment as the app's other buttons (a soft
/// gold-tinted fill + gold border + a subtle lift) — not the stark white rectangle it had before.
private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused: Bool
        var body: some View {
            configuration.label
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(focused ? AnyShapeStyle(Theme.Palette.gold.opacity(0.18)) : AnyShapeStyle(.clear),
                            in: Capsule())
                .overlay { if focused { Capsule().strokeBorder(Theme.Palette.gold, lineWidth: 2) } }
                .scaleEffect(focused ? 1.02 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}
