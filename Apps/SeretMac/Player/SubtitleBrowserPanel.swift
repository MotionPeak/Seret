import DebridCore
import DebridUI
import SwiftUI

/// The ranked subtitle browser (spec §7.4), inside the Audio & Subtitles panel: a language menu,
/// then every OpenSubtitles result ranked ✓ Perfect match / Same release group / Different source.
/// It returns to the tracks only when a pick actually attached; a failed pick explains why, above
/// the list it was picked from, so the list stays to retry from.
struct SubtitleBrowserPanel: View {
    let model: PlayerModel
    let onPicked: () -> Void

    @State private var languages: [SubtitleLanguage] = SubtitleLanguages.fallback
    @State private var picking: Int?
    private let pinned = ["he", "en"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Language", selection: languageBinding) {
                ForEach(SubtitleLanguages.order(languages, pinned: pinned)) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if let failure = model.subtitlePickFailure {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            }

            content
        }
        // Keyed on the playing file: an episode swap clears results back to `.idle`, and an
        // un-keyed task would never search again.
        .task(id: model.contentKey) {
            if let fetched = try? await SubtitleLanguages.fetch(apiKey: Secrets.openSubtitlesAPIKey),
               !fetched.isEmpty { languages = fetched }
            if model.subtitleSearchState == .idle {
                await model.searchSubtitles(language: model.subtitleSearchLanguage ?? pinned[0])
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.subtitleSearchState {
        case .idle, .searching:
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    ShimmerView(cornerRadius: 10).frame(height: 44)
                }
            }
        case .failed:
            if model.subtitlePickFailure == nil {
                message("Couldn't search subtitles. Check the OpenSubtitles account in Settings.")
            }
        case .loaded where model.subtitleSearchResults.isEmpty:
            message("No subtitles found in this language.")
        case .loaded:
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(model.subtitleSearchResults.enumerated()), id: \.element.result.fileID) { index, ranked in
                        resultRow(ranked, index: index)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func resultRow(_ ranked: SubtitleMatch.Ranked, index: Int) -> some View {
        Button {
            picking = index
            Task {
                let attached = await model.useSubtitle(ranked)
                picking = nil
                if attached { onPicked() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(badge(ranked.quality))
                        .font(.system(size: 10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(ranked.quality == .perfect ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    Spacer(minLength: 4)
                    if picking == index {
                        Text("Attaching…").font(.system(size: 10)).foregroundStyle(Theme.Palette.gold)
                    } else if let downloads = ranked.result.downloadCount {
                        Label(downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down")
                            .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Text(ranked.result.release ?? ranked.result.fileName ?? "Subtitle")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(picking != nil)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.body())
            .foregroundStyle(Theme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var languageBinding: Binding<String> {
        Binding(get: { model.subtitleSearchLanguage ?? pinned[0] },
                set: { code in Task { await model.searchSubtitles(language: code) } })
    }

    private func badge(_ quality: SubtitleMatch.Quality) -> String {
        switch quality {
        case .perfect: "✓ PERFECT MATCH"
        case .good: "SAME RELEASE GROUP"
        case .uncertain: "DIFFERENT SOURCE"
        }
    }
}

/// "Sync to a line" (spec §7.4): the line nearest the playhead with its neighbours; ↑↓ pick,
/// Return when you hear it, ←→ nudge a tenth of a second, Esc done. The keys arrive through
/// `PlayerScreen`, which routes them here while a session is open.
struct ManualSyncPanel: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let readout = model.manualSyncReadout {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(readout.lines) { cue in
                        let selected = cue.id == readout.selected.id
                        HStack(alignment: .top, spacing: 8) {
                            Text(Timecode.format(cue.start))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(selected ? Theme.Palette.gold : Theme.Palette.textTertiary)
                                .frame(width: 48, alignment: .leading)
                            Text(cue.text)
                                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .background(selected ? Theme.Palette.gold.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text(readout.offset.map { String(format: "Offset %+.1f s", $0) } ?? "Press Return when you hear the highlighted line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(readout.offset == nil ? Theme.Palette.textSecondary : Theme.Palette.gold)
            } else {
                Text("This subtitle has no lines to sync to.")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            }
            Divider().overlay(Theme.Palette.hairline)
            VStack(alignment: .leading, spacing: 4) {
                hint("↑ ↓", "pick the line")
                hint("Return", "when you hear it")
                hint("← →", "nudge 0.1 s")
                hint("Esc", "done")
            }
        }
    }

    private func hint(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
