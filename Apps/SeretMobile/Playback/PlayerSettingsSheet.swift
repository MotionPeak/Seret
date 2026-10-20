import DebridCore
import DebridUI
import SwiftUI

/// Which pill opened the playback panel — its section leads.
enum PlayerSettingsSection: String, Identifiable {
    case audio, subtitles, speed
    var id: String { rawValue }
}

/// The player's playback panel: audio, subtitles (existing + on-demand he/en, search, sync,
/// timing), speed and the volume boost — each laid out as wrapping chips (selected = white), not a
/// vertical list. A glass sheet on iPhone; on iPad a popover over the pills, not a sheet stretched
/// across the screen (audit). The pill that opened it decides which sections come first.
struct PlayerSettingsSheet: View {
    let model: PlayerModel
    var focus: PlayerSettingsSection?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    switch focus {
                    case .subtitles:
                        subtitlesSection
                        timingSection
                        audioSection
                        volumeSection
                        speedSection
                    case .speed:
                        speedSection
                        audioSection
                        volumeSection
                        subtitlesSection
                        timingSection
                    case .audio, nil:
                        audioSection
                        volumeSection
                        subtitlesSection
                        timingSection
                        speedSection
                    }
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .defaultScrollAnchor(Self.openingAnchor)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
        .tint(Theme.Palette.focus)
    }

    /// Top, always — except a DEBUG harness launched with `-uiPreviewAnchor bottom`, which opens
    /// at the end so a screenshot can show the last section is reachable.
    private static var openingAnchor: UnitPoint {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "uiPreviewAnchor") == "bottom" { return .bottom }
        #endif
        return .top
    }

    private var navigationTitle: String {
        switch focus {
        case .subtitles: "Subtitles"
        case .audio: "Audio"
        case .speed: "Speed"
        case nil: "Playback"
        }
    }

    private var audioSection: some View {
        section("Audio", "speaker.wave.2.fill") {
            if model.audioTracks.isEmpty {
                Text("No alternate tracks")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                FlowLayout {
                    ForEach(labeled(model.audioTracks), id: \.track.id) { e in
                        chip(e.label, selected: model.displayedAudioID == e.track.id) {
                            model.selectAudio(id: e.track.id)
                        }
                    }
                }
            }
        }
    }

    private var subtitlesSection: some View {
        section("Subtitles", "captions.bubble.fill") {
            // Grouped, as on tvOS, because the two groups can name the same language:
            // a release with a Hebrew track inside it AND a Hebrew subtitle fetched for
            // it put two identically-labelled chips side by side, one ticked and one
            // not, with nothing to say which was which.
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                FlowLayout {
                    chip("Off", selected: model.displayedSubtitleID == nil) { model.selectSubtitleOff() }
                    // Muxed tracks shipped inside the file.
                    ForEach(labeled(model.embeddedTracks), id: \.track.id) { e in
                        chip(e.label, selected: model.displayedSubtitleID == e.track.id) {
                            model.selectSubtitle(id: e.track.id)
                        }
                    }
                }
                // Attached from a download this session (auto he/en or a browser pick).
                if !model.downloadedTracks.isEmpty {
                    groupCaption("DOWNLOADED")
                    FlowLayout {
                        ForEach(labeled(model.downloadedTracks), id: \.track.id) { e in
                            chip(e.label, selected: model.displayedSubtitleID == e.track.id) {
                                model.selectSubtitle(id: e.track.id)
                            }
                        }
                    }
                }
                FlowLayout {
                    // One-click he/en for the common case (no muxed subs). Hidden once
                    // the track is attached, since it then appears above instead.
                    ForEach(model.subtitleRows) { row in
                        if model.attachedTrackID(row) == nil { quickChip(row) }
                    }
                    searchChip
                }
            }
        }
    }

    // The last resort when a subtitle still does not line up — and the ONLY one available for a
    // muxed track, which cannot be rewritten the way a downloaded file is on the way in.
    private var timingSection: some View {
        section(timingTitle, "timer") {
            FlowLayout {
                // The automatic answer first. Only for a subtitle we downloaded — a
                // muxed track is timed against this file by construction.
                //
                // Tapping it closes the sheet: the measurement takes minutes, and the
                // point of it running in the background is that the viewer goes back to
                // the film. It reports from the bar across the top of the picture.
                if model.canAutoSyncSubtitle {
                    chip(autoSyncTitle, selected: model.autoSyncState == .synced) {
                        model.startAutoSync()
                        dismiss()
                    }
                    .disabled(model.autoSyncState == .measuring)
                }
                chip("−0.5s", selected: false) { model.adjustSubtitleDelay(by: -0.5) }
                chip("+0.5s", selected: false) { model.adjustSubtitleDelay(by: 0.5) }
                chip("Reset", selected: false) { model.resetSubtitleDelay() }
                // The muxed-track answer — an offset recomputed every tick, which
                // grows as fast as the drift does. See the tvOS panel for why 25fps.
                chip("25fps (PAL)", selected: model.isCorrectingSubtitleDrift) {
                    model.setSubtitleSourceFPS(
                        model.isCorrectingSubtitleDrift ? nil : 25)
                }
            }
            // A built-in track only moves as far as libvlc can reach — see the tvOS
            // panel. A downloaded one is rewritten, so this never shows for it.
            if model.subtitleOffsetBeyondEmbeddedReach {
                Text(PlayerModel.embeddedSubtitleReachNote)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var speedSection: some View {
        section("Speed", "speedometer") {
            FlowLayout {
                ForEach(Self.speeds, id: \.value) { opt in
                    chip(opt.label, selected: model.playbackSpeed == opt.value) {
                        model.setPlaybackSpeed(opt.value)
                    }
                }
            }
        }
    }

    private var volumeSection: some View {
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

    @ViewBuilder private func section<C: View>(_ title: String, _ icon: String,
                                              @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label(title, systemImage: icon)
                .font(Theme.Typo.label()).tracking(1).foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
    }

    /// A small sub-header separating muxed tracks from ones downloaded this session.
    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).tracking(1)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.Palette.onFocus : Theme.Palette.textPrimary)
            .padding(.vertical, 9).padding(.horizontal, 15)
            .background(selected ? AnyShapeStyle(Theme.Palette.focus)
                                 : AnyShapeStyle(Theme.Palette.glassFaint), in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    /// What the auto-sync chip says, which is also its only progress indicator — it listens to a
    /// few minutes of the film, so it is not instant and must not look stuck.
    private var autoSyncTitle: String {
        switch model.autoSyncState {
        case .idle:      "Sync automatically"
        case .measuring: "Listening…"
        case .synced:    "Synced"
        case .failed:    "Couldn't match audio"
        }
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
            .background(Theme.Palette.glassFaint, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.focus.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled(row))
    }

    @ViewBuilder private func downloadGlyph(_ state: PlayerModel.SubtitleRowState) -> some View {
        switch state {
        case .idle:        Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.textPrimary)
        case .downloading: ProgressView().controlSize(.mini)
        case .attached:    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.textPrimary)
        case .capReached:  Image(systemName: "clock").foregroundStyle(Theme.Palette.textSecondary)
        case .noAccount:   Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(Theme.Palette.textSecondary)
        case .error:       Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.textPrimary)
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
            .background(Theme.Palette.glassFaint, in: Capsule())
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The timing section's title doubles as its readout: whether the attached subtitle was
    /// already rate-corrected on the way in, and whatever offset has been dialled on top.
    private var timingTitle: String {
        var parts = ["Subtitle timing"]
        if model.subtitleRetimeFactor != nil { parts.append("rate-corrected") }
        if model.isCorrectingSubtitleDrift {
            parts.append(String(format: "PAL %+.0fs", model.subtitleDriftDelay))
        }
        if model.subtitleDelay != 0 { parts.append(String(format: "%+.1fs", model.subtitleDelay)) }
        return parts.joined(separator: " · ")
    }

    static let speeds: [(label: String, value: Double)] =
        [("0.5×", 0.5), ("0.75×", 0.75), ("Normal", 1.0), ("1.25×", 1.25), ("1.5×", 1.5)]

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

/// The panel's background: iOS 26 sheets and popovers are Liquid Glass of their own, so nothing is
/// painted over them; iOS 18 gets a dark material, the picture showing through either way — it was
/// an opaque canvas before.
private struct GlassSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !GlassSupport.forceFallback {
            content
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
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
            // Why the last pick produced nothing, above the list it was picked from — so the
            // answer is where the viewer is already looking, and the list stays to retry from.
            if let failure = model.subtitlePickFailure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                .listRowBackground(Theme.Palette.focus.opacity(0.16))
            }
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
                // The banner below carries the actual reason; only speak up if there isn't one.
                if model.subtitlePickFailure == nil {
                    Text("Couldn't search subtitles. Check the OpenSubtitles account in Settings.")
                        .foregroundStyle(.secondary)
                }
            case .loaded where model.subtitleSearchResults.isEmpty:
                Text("No subtitles found in this language.").foregroundStyle(.secondary)
            case .loaded:
                ForEach(model.subtitleSearchResults, id: \.result.fileID) { ranked in
                    Button {
                        // Dismiss only when a subtitle actually reached the engine. It used to
                        // dismiss unconditionally, so a pick that failed took the list away
                        // having changed nothing — indistinguishable from being ignored.
                        Task { if await model.useSubtitle(ranked) { dismiss() } }
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
        // Keyed on the playing file. The browser's results belong to one file, and an episode
        // swap or a "Try another version" clears them back to `.idle` — which this view draws with
        // the same spinner as `.searching`. An un-keyed task runs once on appear and never again,
        // so the browser sat on "Searching…" for good, with no search running to finish it.
        .task(id: model.contentKey) {
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
