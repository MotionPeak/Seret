import SwiftUI
import DebridUI
import DebridCore

/// The top-down player settings panel — modeled on the native tvOS player overlay.
/// Three tabs (Info · Playback Settings · Technical Details); Playback Settings shows
/// Audio Streams, Subtitles, and Playback Speed columns.
struct SettingsPanel: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void
    @State private var tab: Tab = .playback
    @FocusState private var focusedTab: Tab?
    @Namespace private var scope

    enum Tab: String, CaseIterable {
        case info = "Info", playback = "Playback Settings", technical = "Technical Details"
    }

    var body: some View {
        VStack(spacing: 24) {
            // Tab bar — switches on FOCUS (no click needed), like the native tvOS player overlay.
            HStack(spacing: 14) {
                ForEach(Tab.allCases, id: \.self) { t in
                    TabChip(title: t.rawValue, selected: tab == t)
                        .focusable()
                        .focused($focusedTab, equals: t)
                }
            }
            .padding(.top, 28)
            .onChange(of: focusedTab) { _, newValue in
                if let newValue { tab = newValue }     // moving across the top switches tabs live
            }

            // Body.
            Group {
                switch tab {
                case .info:      InfoColumn(model: model)
                case .playback:  PlaybackColumns(model: model, onPick: onClose)
                case .technical: TechnicalColumn(model: model)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            // Dark translucent backdrop — matches the native player.
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.78))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10), lineWidth: 1))
        )
        .padding(.horizontal, 60)
        .padding(.top, 40)                // sits at the top of the screen
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusScope(scope)
    }
}

// MARK: - Playback Settings columns

private struct PlaybackColumns: View {
    @Bindable var model: PlayerModel
    let onPick: () -> Void
    /// Seeds focus to the "Subtitles → Off" row when the panel opens, so the arrows navigate the
    /// options immediately — no extra click to "enter" the menu. `.defaultFocus` is declarative, so
    /// it lands without the flaky async + prefersDefaultFocus combo it replaces.
    @FocusState private var landingFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            audioColumn
            subtitlesColumn
            speedColumn
        }
        .defaultFocus($landingFocused, true)
    }

    private var audioColumn: some View {
        SettingsColumn(header: "AUDIO STREAMS") {
            ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                CheckRow(title: entry.label, checked: false) {
                    model.selectAudio(id: entry.track.id); onPick()
                }
            }
            if model.audioTracks.isEmpty {
                Text("None").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitlesColumn: some View {
        SettingsColumn(header: "SUBTITLES") {
            CheckRow(title: "Off", checked: model.selectedSubtitleID == nil) { model.selectSubtitleOff(); onPick() }
                .focused($landingFocused)         // first focused when the panel opens
            ForEach(labeled(model.embeddedSubtitleTracks), id: \.track.id) { entry in
                CheckRow(title: entry.label, checked: model.selectedSubtitleID == entry.track.id) {
                    model.selectSubtitle(id: entry.track.id); onPick()
                }
            }
            ForEach(model.subtitleRows) { row in
                if let attachedID = model.attachedTrackID(row) {
                    // Downloaded → the language row IS the track (selectable, no duplicate "Track N").
                    CheckRow(title: row.language == "he" ? "Hebrew" : "English",
                             checked: model.selectedSubtitleID == attachedID) {
                        model.selectSubtitle(id: attachedID); onPick()
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

// MARK: - Info / Technical

private struct InfoColumn: View {
    @Bindable var model: PlayerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.label).font(.title2.bold())
            Text(timeLine).font(.body).foregroundStyle(.secondary).monospacedDigit()
        }
    }
    private var timeLine: String {
        "\(Timecode.format(model.position)) / \(Timecode.format(model.duration))"
    }
}

private struct TechnicalColumn: View {
    @Bindable var model: PlayerModel
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            SettingsColumn(header: "AUDIO TRACKS") {
                ForEach(model.audioTracks) { Text($0.name).font(.callout) }
                if model.audioTracks.isEmpty { Text("—").font(.callout).foregroundStyle(.secondary) }
            }
            SettingsColumn(header: "SUBTITLES") {
                ForEach(model.subtitleTracks) { Text($0.name).font(.callout) }
                if model.subtitleTracks.isEmpty { Text("—").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Building blocks

private struct SettingsColumn<Content: View>: View {
    let header: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(header).font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.2)
            content
        }
        .frame(minWidth: 220, alignment: .leading)
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
                    .opacity(checked ? 1 : 0)
                Text(title).font(.callout)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

/// A top tab styled for focus: a bright white pill when focused, a faint pill for the selected
/// (current) tab, plain otherwise. Reads `\.isFocused` directly so the highlight is uniform rather
/// than the inconsistent default-button glow.
private struct TabChip: View {
    let title: String
    let selected: Bool
    @Environment(\.isFocused) private var focused: Bool
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(fill, in: Capsule())
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
    private var fill: Color {
        if focused { return .white }
        if selected { return .white.opacity(0.22) }
        return .white.opacity(0.08)
    }
}

/// A settings row's focus look: a clean white pill + dark text + a subtle lift, replacing the
/// inconsistent default `.plain` highlight (the "buggy glow").
private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused: Bool
        var body: some View {
            configuration.label
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(focused ? .black : .white)
                .background(focused ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10))
                .scaleEffect(focused ? 1.03 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
