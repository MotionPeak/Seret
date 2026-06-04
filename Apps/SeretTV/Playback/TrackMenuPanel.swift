import SwiftUI
import DebridCore

/// The Subtitles & Audio side panel. Two tabs (Subtitles · Audio) keep the long track lists from
/// piling into one messy column; each shows a clean, de-duplicated, language-named list.
struct TrackMenuPanel: View {
    @Bindable var model: PlayerModel
    @State private var tab: Tab = .subtitles

    enum Tab: String, CaseIterable { case subtitles = "Subtitles", audio = "Audio" }

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.35)   // dim; non-interactive (close via Menu — handled by PlayerView)
            VStack(alignment: .leading, spacing: 26) {
                tabBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .subtitles: subtitlesList
                        case .audio:     audioList
                        }
                    }
                    .padding(.trailing, 8)
                    .focusSection()   // ensures focus lands in the list when the panel opens
                }
            }
            .padding(40)
            .frame(width: 640)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tab == t ? Color.black : Color.white)   // readable in both states
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(tab == t ? Color.white : Color.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)   // .bordered's white tint hid the selected label (white-on-white)
            }
        }
    }

    // MARK: - Subtitles

    @ViewBuilder private var subtitlesList: some View {
        Button("Off") { model.selectSubtitleOff() }
        ForEach(labeled(model.subtitleTracks), id: \.track.id) { entry in
            Button(entry.label) { model.selectSubtitle(id: entry.track.id) }
        }
        Text("Download from OpenSubtitles")
            .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
        ForEach(model.subtitleRows) { row in
            SubtitleRowButton(row: row) { Task { await model.requestSubtitle(language: row.language) } }
        }
    }

    // MARK: - Audio

    @ViewBuilder private var audioList: some View {
        if model.audioTracks.isEmpty {
            Text("No audio tracks").font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(labeled(model.audioTracks), id: \.track.id) { entry in
                Button(entry.label) { model.selectAudio(id: entry.track.id) }
            }
        }
    }

    // MARK: - Clean names

    /// Turn VLCKit's raw "Track 3 - [German]" names into clean, de-duplicated labels
    /// ("German", "German 2", …). Prefers the bracketed language, then the language code.
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

private struct SubtitleRowButton: View {
    let row: PlayerModel.SubtitleRow
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(displayName)
                Spacer()
                trailing
            }
        }
        .disabled(isDisabled)
    }
    private var displayName: String { row.language == "he" ? "Hebrew" : "English" }
    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .idle: Image(systemName: "arrow.down.circle")
        case .downloading: ProgressView()
        case .attached: Image(systemName: "checkmark")
        case .capReached(let reset): Text(reset == nil ? "Daily limit" : "Resets \(reset!.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        case .error: Text("Retry").foregroundStyle(.orange)
        case .noAccount: Text("Add account in Settings").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var isDisabled: Bool { if case .capReached = row.state { return true }; if case .noAccount = row.state { return true }; if case .downloading = row.state { return true }; return false }
}
