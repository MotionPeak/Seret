import DebridCore
import DebridUI
import SwiftUI

/// Spec §7.2's windowed HUD: a top bar (back, title + quality chips), a two-row glass panel
/// (scrubber with times; volume · ⟲10 ▶ ⟳10 · audio & subtitles · full screen), scrims, the
/// Audio & Subtitles panel, and the Up Next card. `PlayerScreen` owns visibility, focus and the
/// keyboard; this view is the layout.
struct PlayerHUD: View {
    let model: PlayerModel
    let hud: HUDVisibility
    let windowRef: WindowRef
    @Binding var tracksPanelOpen: Bool
    @Binding var panelMode: TracksPanelMode
    @Binding var episodesOpen: Bool
    let onClose: () -> Void
    let onToggleFullScreen: () -> Void
    let onToggleMute: () -> Void

    @State private var isDraggingScrub = false
    @State private var scrubPreviewTime: Double?
    @State private var width: CGFloat = 1200

    private var style: PlayerHUDStyle { .current(isFullScreen: windowRef.isFullScreen) }

    var body: some View {
        ZStack {
            if hud.isVisible {
                scrims
                topBar
                switch style {
                case .windowed: panel
                case .fullScreen: compactBar
                }
            }
            if tracksPanelOpen {
                tracksPanelLayer
            }
            if episodesOpen, model.isEpisode, !model.seasonEpisodes.isEmpty {
                episodesLayer
            }
            if model.upNextVisible, let next = model.nextEpisode {
                upNextLayer(next)
            }
            if let feedback = model.skipFeedback {
                SkipBadge(feedback: feedback)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: feedback.seconds < 0 ? .leading : .trailing)
                    .padding(.horizontal, 80)
                    .transition(.opacity)
                    .id(feedback.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: isDraggingScrub) { _, dragging in hud.isScrubbing = dragging }
        .onChange(of: tracksPanelOpen) { _, open in hud.panelOpen = open }
        .animation(Theme.Motion.fade, value: hud.isVisible)
        .animation(Theme.Motion.fade, value: tracksPanelOpen)
        .animation(Theme.Motion.fade, value: model.upNextVisible)
        .animation(Theme.Motion.fade, value: episodesOpen)
        .animation(Theme.Motion.fade, value: model.skipFeedback?.id)
    }

    // MARK: - Scrims

    private var scrims: some View {
        let topFraction = windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.scrimTopFraction : 0.26
        let topOpacity = windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.scrimTopOpacity : 0.66
        let bottomFraction = windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.scrimBottomFraction : 0.42
        let bottomOpacity = windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.scrimBottomOpacity : 0.78
        return GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(topOpacity), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * topFraction)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black.opacity(bottomOpacity)], startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * bottomFraction)
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack(spacing: windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.topBarGap : 14) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.iconButton, height: PlayerHUDMetrics.iconButton)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back (Esc)")

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.label)
                        .font(.system(size: windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.titleFont : 15,
                                     weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    if !qualityChips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(qualityChips, id: \.self) { chip($0) }
                        }
                    }
                }
                Spacer()
            }
            .padding(.leading, windowRef.isFullScreen
                     ? PlayerHUDMetrics.topBarLeadingFullScreen : PlayerHUDMetrics.topBarLeadingWindowed)
            .padding(.trailing, PlayerHUDMetrics.sideMargin)
            .padding(.top, windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.topBarTop : PlayerHUDMetrics.topBarTop)
            .onHover { hud.pointerOverControls = $0 }
            Spacer()
        }
        .transition(.opacity)
    }

    private var qualityChips: [String] {
        let parsed = model.currentSource.parsed
        return [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: windowRef.isFullScreen ? PlayerHUDMetrics.FullScreen.chipFont : 10, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary.opacity(windowRef.isFullScreen ? 0.8 : 1))
            .padding(.horizontal, windowRef.isFullScreen ? 6 : 8)
            .padding(.vertical, windowRef.isFullScreen ? 2 : 3)
            .background(Theme.Palette.chipFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Panel

    private var panel: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                scrubberRow
                controlsRow
            }
            .padding(16)
            .frame(width: PlayerHUDMetrics.panelWidth(windowWidth: width))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: PlayerHUDMetrics.panelCorner, style: .continuous))
            .onHover { hud.pointerOverControls = $0 }
            .padding(.bottom, PlayerHUDMetrics.panelBottom)
        }
        .transition(.opacity)
    }

    private var scrubberRow: some View {
        VStack(spacing: 6) {
            Scrubber(position: model.position, duration: model.duration,
                    onCommit: { model.scrub(to: $0) },
                    isDragging: $isDraggingScrub, previewTime: $scrubPreviewTime)
            HStack {
                Text(Timecode.format(scrubPreviewTime ?? model.position))
                Spacer()
                Text(Timecode.format(model.duration))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var controlsRow: some View {
        HStack {
            HStack(spacing: 10) {
                Button(action: onToggleMute) {
                    Image(systemName: model.volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: PlayerHUDMetrics.icon))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.iconButton, height: PlayerHUDMetrics.iconButton)
                }
                .buttonStyle(.plain)
                .help("Mute (M)")
                Slider(value: Binding(get: { Double(model.volumePercent) },
                                      set: { model.setVolume(Int($0)) }), in: 0...200)
                    .frame(width: 110)
                    .tint(Theme.Palette.gold)
            }
            Spacer()
            HStack(spacing: 18) {
                iconButton("gobackward.10", help: "Back 10 s (←)") { model.skip(-10) }
                Button(action: { model.togglePlayPause() }) {
                    Image(systemName: model.phase == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: PlayerHUDMetrics.playIcon))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.playButton, height: PlayerHUDMetrics.playButton)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Play/Pause (Space)")
                iconButton("goforward.10", help: "Forward 10 s (→)") { model.skip(10) }
            }
            Spacer()
            HStack(spacing: 10) {
                if model.isEpisode {
                    iconButton("rectangle.stack", help: "Episodes (E)", tinted: episodesOpen) { episodesOpen.toggle() }
                }
                if model.hasNextEpisode {
                    iconButton("forward.end.fill", help: "Next Episode (N)") { model.playNext() }
                }
                Button(action: { tracksPanelOpen.toggle() }) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: PlayerHUDMetrics.icon))
                        .foregroundStyle(tracksPanelOpen ? Theme.Palette.gold : Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.iconButton, height: PlayerHUDMetrics.iconButton)
                }
                .buttonStyle(.plain)
                .help("Audio & Subtitles")
                Button(action: onToggleFullScreen) {
                    Image(systemName: windowRef.isFullScreen
                          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: PlayerHUDMetrics.icon))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.iconButton, height: PlayerHUDMetrics.iconButton)
                }
                .buttonStyle(.plain)
                .help(windowRef.isFullScreen ? "Exit Full Screen (F)" : "Full Screen (F)")
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, tinted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PlayerHUDMetrics.icon))
                .foregroundStyle(tinted ? Theme.Palette.gold : Theme.Palette.textPrimary)
                .frame(width: PlayerHUDMetrics.iconButton, height: PlayerHUDMetrics.iconButton)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Full-screen compact bar

    /// Spec §7.2's full-screen bar: one translucent single-row pill — ⟲10 ⏯ ⟳10 · elapsed · a thin
    /// scrubber · remaining │ audio & subtitles · volume · exit full screen — sized from
    /// `PlayerHUDMetrics.FullScreen`, never the windowed panel's numbers.
    private var compactBar: some View {
        VStack {
            Spacer()
            HStack(spacing: PlayerHUDMetrics.FullScreen.barGap) {
                compactIconButton("gobackward.10", help: "Back 10 s (←)") { model.skip(-10) }
                Button(action: { model.togglePlayPause() }) {
                    Image(systemName: model.phase == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: PlayerHUDMetrics.FullScreen.playIcon))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: PlayerHUDMetrics.FullScreen.playButton,
                              height: PlayerHUDMetrics.FullScreen.playButton)
                }
                .buttonStyle(.plain)
                .help("Play/Pause (Space)")
                compactIconButton("goforward.10", help: "Forward 10 s (→)") { model.skip(10) }

                Text(Timecode.format(scrubPreviewTime ?? model.position))
                    .frame(minWidth: PlayerHUDMetrics.FullScreen.timeMinWidth)
                Scrubber(position: model.position, duration: model.duration,
                        onCommit: { model.scrub(to: $0) },
                        isDragging: $isDraggingScrub, previewTime: $scrubPreviewTime)
                    .frame(height: PlayerHUDMetrics.FullScreen.scrubHeight)
                Text("-" + Timecode.format(max(0, model.duration - (scrubPreviewTime ?? model.position))))
                    .frame(minWidth: PlayerHUDMetrics.FullScreen.timeMinWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: PlayerHUDMetrics.FullScreen.separatorHeight)

                if model.isEpisode {
                    compactIconButton("rectangle.stack", help: "Episodes (E)", tinted: episodesOpen) {
                        episodesOpen.toggle()
                    }
                }
                compactIconButton("captions.bubble", help: "Audio & Subtitles", tinted: tracksPanelOpen) {
                    tracksPanelOpen.toggle()
                }
                compactIconButton(model.volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  help: "Mute (M)", action: onToggleMute)
                compactIconButton("arrow.down.right.and.arrow.up.left", help: "Exit Full Screen (F)",
                                  action: onToggleFullScreen)
            }
            .font(.system(size: PlayerHUDMetrics.FullScreen.timeFont).monospacedDigit())
            .foregroundStyle(.white.opacity(0.78))
            .padding(.vertical, PlayerHUDMetrics.FullScreen.barPaddingV)
            .padding(.horizontal, PlayerHUDMetrics.FullScreen.barPaddingH)
            .frame(width: PlayerHUDMetrics.FullScreen.barWidth(windowWidth: width))
            .glassEffect(.regular, in: Capsule())
            .onHover { hud.pointerOverControls = $0 }
            .padding(.bottom, PlayerHUDMetrics.FullScreen.barBottom)
        }
        .transition(.opacity)
    }

    private func compactIconButton(_ symbol: String, help: String, tinted: Bool = false,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PlayerHUDMetrics.FullScreen.icon))
                .foregroundStyle(tinted ? Theme.Palette.gold : Theme.Palette.textPrimary)
                .frame(width: PlayerHUDMetrics.FullScreen.iconButton, height: PlayerHUDMetrics.FullScreen.iconButton)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Tracks panel

    private var tracksPanelLayer: some View {
        TracksPanel(model: model, mode: $panelMode, onClose: { tracksPanelOpen = false })
            .padding(.top, 20)
            .padding(.bottom, windowRef.isFullScreen
                     ? PlayerHUDMetrics.FullScreen.clearOfBar : PlayerHUDMetrics.clearOfBottomPanel)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .transition(.opacity)
    }

    // MARK: - Episodes

    private var episodesLayer: some View {
        VStack {
            Spacer()
            EpisodeStrip(model: model, onClose: { episodesOpen = false })
                .frame(maxWidth: 980)
        }
        .padding(.horizontal, PlayerHUDMetrics.sideMargin)
        .padding(.bottom, windowRef.isFullScreen
                 ? PlayerHUDMetrics.FullScreen.clearOfBar : PlayerHUDMetrics.clearOfBottomPanel)
        .transition(.opacity)
    }

    // MARK: - Up Next

    private func upNextLayer(_ next: Episode) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                UpNextCard(episodeTitle: "S\(next.season)·E\(next.number)",
                          seconds: model.upNextSecondsRemaining,
                          onPlayNow: { model.playNextNow() },
                          onDismiss: { model.dismissUpNext() })
            }
        }
        .padding(.trailing, PlayerHUDMetrics.sideMargin)
        .padding(.bottom, windowRef.isFullScreen
                 ? PlayerHUDMetrics.FullScreen.clearOfBar : PlayerHUDMetrics.clearOfBottomPanel)
        .transition(.opacity)
    }
}
