import SwiftUI
import DebridUI
import DebridCore

/// The top-down player settings panel — just the three things you actually change mid-playback:
/// Audio Streams, Subtitles, and Playback Speed. (No Info / Technical tabs.)
struct SettingsPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        PlaybackColumns(model: model, onPick: onClose)
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Dark translucent backdrop — matches the native player.
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.Palette.canvas.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.Palette.gold.opacity(0.18), lineWidth: 1))
            )
            .padding(.horizontal, 60)
            .padding(.top, 40)                // sits at the top of the screen
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Playback Settings columns

private struct PlaybackColumns: View {
    @Bindable var model: PlayerModel
    let onPick: () -> Void
    /// Seeds focus to the "Subtitles → Off" row when the panel opens, so the arrows navigate the
    /// options immediately — no extra click to "enter" the menu. Uses the same `@FocusState` +
    /// `.onAppear` seed as the sibling overlays (`UpNextBar`, `EpisodesPanel`) — reliable across the
    /// UIKit `ScrubPad` → SwiftUI focus handoff, unlike the `.defaultFocus`/`.focusScope` combo it
    /// replaces (which stranded focus and left the panel uncontrollable).
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
                Text("None").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitlesColumn: some View {
        SettingsColumn(header: "SUBTITLES") {
            CheckRow(title: "Off", checked: model.selectedSubtitleID == nil) { model.selectSubtitleOff() }
                .focused($landingFocused)         // first focused when the panel opens
            ForEach(labeled(model.embeddedSubtitleTracks), id: \.track.id) { entry in
                CheckRow(title: entry.label, checked: model.selectedSubtitleID == entry.track.id) {
                    model.selectSubtitle(id: entry.track.id)
                }
            }
            ForEach(model.subtitleRows) { row in
                if let attachedID = model.attachedTrackID(row) {
                    // Downloaded → the language row IS the track (selectable, no duplicate "Track N").
                    CheckRow(title: row.language == "he" ? "Hebrew" : "English",
                             checked: model.selectedSubtitleID == attachedID) {
                        model.selectSubtitle(id: attachedID)
                    }
                } else {
                    let title = row.language == "he" ? "Hebrew (download)" : "English (download)"
                    CheckRow(title: title, checked: false) {
                        Task { await model.requestSubtitle(language: row.language) }
                    }
                    .disabled(isDisabled(row))
                }
            }
        }
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

    private func isDisabled(_ row: PlayerModel.SubtitleRow) -> Bool {
        switch row.state {
        case .capReached, .noAccount, .downloading: return true
        default: return false
        }
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
        if let r = track.name.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            let inner = track.name[r].dropFirst().dropLast()
            if !inner.isEmpty { return String(inner) }
        }
        if let l = track.language, !l.isEmpty { return l.capitalized }
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
            Text(header).font(.caption.weight(.bold))
                .foregroundStyle(Theme.Palette.gold)
                .tracking(1.2)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.vertical, 2)   // a little room so the focus pill isn't clipped
            }
        }
        .frame(minWidth: 220, maxHeight: 640, alignment: .leading)
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
                    .font(.callout.bold())
                    .foregroundStyle(Theme.Palette.gold)
                    .opacity(checked ? 1 : 0)
                Text(title).font(.callout)
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
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(focused ? AnyShapeStyle(Theme.Palette.gold.opacity(0.18)) : AnyShapeStyle(.clear),
                            in: Capsule())
                .overlay { if focused { Capsule().strokeBorder(Theme.Palette.gold, lineWidth: 2) } }
                .scaleEffect(focused ? 1.04 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
