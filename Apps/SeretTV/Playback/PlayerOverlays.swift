import SwiftUI
import DebridUI
import DebridCore

struct LoadingOverlay: View {
    let caption: String
    let title: String
    let backdropURL: URL?
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 18) {
                ProgressView().controlSize(.large).tint(Theme.Palette.textPrimary)
                Text(caption)
                    .font(.seret(30, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(title)
                    .font(.seret(24, .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ErrorOverlay: View {
    let reason: String
    let canTryAnother: Bool
    let backdropURL: URL?
    let onRetry: () -> Void
    let onTryAnother: () -> Void
    let onBack: () -> Void
    var body: some View {
        DimBackdrop(url: backdropURL) {
            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Couldn't play this source")
                    .font(.seret(40, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(reason)
                    .font(.seret(25, .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 800)
                HStack(spacing: 22) {
                    Button("Retry", action: onRetry)
                        .buttonStyle(SeretActionButtonStyle(prominent: true))
                    if canTryAnother {
                        Button("Try another version", action: onTryAnother)
                            .buttonStyle(SeretActionButtonStyle())
                    }
                    Button("Back", action: onBack)
                        .buttonStyle(SeretActionButtonStyle())
                }
                .padding(.top, 12)
            }
        }
    }
}

private struct DimBackdrop<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black
            // RemoteImage (not AsyncImage): keeps the decoded backdrop in ImageMemoryCache so a
            // retry or an episode-swap reload doesn't re-fetch and re-decode it — the flash 40387ee
            // removed everywhere else in the app.
            if let url { RemoteImage(url: url, contentMode: .fill) { _ in Color.clear } }
            Color.black.opacity(0.72)
            content
        }
        .ignoresSafeArea()
    }
}

// MARK: - Bars over the picture

/// "Logged to Letterboxd", for three seconds, when an entry actually lands.
///
/// Nothing appears for a failed write: it is not actionable while a film is playing, and the
/// Letterboxd settings card carries it.
struct LetterboxdLoggedBar: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .semibold))
            Text("Logged to Letterboxd")
                .font(.seret(24, .semibold))
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, 34).padding(.vertical, 20)
        .playerOverlaySurface(Capsule())
        // Below `PlayerTopBar`'s title block, so the two never overlap — and off the top edge a
        // real television overscans.
        .padding(.top, PlayerLayout.topSlotInset)
    }
}

/// The post-credits prompt: ten stars, and a way out.
///
/// Sits in the same slot as the logged confirmation because it is the same bar at an earlier
/// moment — the entry is already queued, and this is what it is waiting for.
///
/// 🚨 Focusable. `PlayerView` guards it behind `isAskingRating` and drops `PlayerInputSurface`
/// for as long as it is up: a focusable sibling at rest is what made touch-scrub and arrow clicks
/// mutually exclusive.
struct LetterboxdRatingBar: View {
    let current: Int?
    var focus: FocusState<PlayerFocus?>.Binding
    let onRate: (Int?) -> Void
    let onDismiss: () -> Void

    /// What the row is aimed at right now: the focused star, falling back to the rating the film
    /// already carries. tvOS has no hover, so per-star focus is what makes the row fill and the
    /// heading count up as the remote travels — and seeing "Rate it 8/10" before pressing is what
    /// stops a mis-press filing the wrong score.
    private var shown: Int {
        if case .rating(let value) = focus.wrappedValue { return value }
        return current ?? 0
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("LOGGING TO LETTERBOXD")
                .font(.seret(.caption1, .semibold)).kerning(1.5)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(shown > 0 ? "Rate it \(shown)/10" : "Rate it?")
                .font(.seret(26, .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())

            HStack(spacing: 14) {
                ForEach(1...10, id: \.self) { value in
                    Button { onRate(value) } label: {
                        Image(systemName: shown >= value ? "star.fill" : "star")
                            .font(.title3)
                            .padding(6)
                    }
                    .buttonStyle(RatingStarStyle(filled: shown >= value))
                    .focused(focus, equals: .rating(value))
                    .accessibilityLabel("Rate \(value) out of 10")
                }
            }
            .focusSection()

            Text("Press Menu to log it without a rating.")
                .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, 44).padding(.vertical, 26)
        .playerOverlaySurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
        // Sized to its contents and kept off the edges. Left to fill the width it ran almost
        // bezel to bezel, which a real television overscans into.
        .fixedSize(horizontal: true, vertical: false)
        // The same top slot the other bars use, below `PlayerTopBar`.
        .padding(.top, PlayerLayout.topSlotInset)
        // Opens aimed at the rating the film already has — a rewatch starts from your own score —
        // and at the leftmost star otherwise. Never a guess: any seeded middle value is a score
        // the viewer did not choose sitting one press away from being filed.
        .onAppear { focus.wrappedValue = .rating(current ?? 1) }
        .onDisappear { focus.wrappedValue = nil }
    }
}

/// The rating prompt before the viewer has chosen to answer it: the same bar, with nothing to
/// focus. The film is still playing, usually its credits, so the remote keeps its jobs — Select
/// pauses, the arrows skip — and Up is the deliberate step into the stars (see `isRating`).
struct LetterboxdRatingInvite: View {
    let current: Int?

    var body: some View {
        VStack(spacing: 12) {
            Text("LOGGING TO LETTERBOXD")
                .font(.seret(.caption1, .semibold)).kerning(1.5)
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: 12) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                Text(current.map { "Press up to change your \($0)/10" } ?? "Press up to rate it")
                    .font(.seret(26, .semibold))
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            Text("Press Menu to log it without a rating.")
                .font(.seretCaption).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, 44).padding(.vertical, 26)
        .playerOverlaySurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.top, PlayerLayout.topSlotInset)
    }
}

/// A chrome-free star, matching the title page's `UserRatingRow`. tvOS draws a grey rounded
/// platter behind every `.card` button, so ten of them read as ten grey boxes instead of a rating;
/// a custom style is the only way to suppress it.
private struct RatingStarStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Render(configuration: configuration, filled: filled)
    }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        let filled: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(filled || focused ? Theme.Palette.focus : Color.white.opacity(0.45))
                .scaleEffect(focused ? 1.35 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}

/// The strip across the top of the picture while a subtitle sync runs, and for a few seconds after
/// it finishes.
///
/// It exists because the measurement takes minutes: it has to read several minutes of the film's
/// audio, which means downloading them. Holding the viewer on the settings sheet for that would be
/// unusable, so the sheet closes, the film keeps playing, and this is where the work reports from.
///
/// Deliberately built out of nothing focusable and marked `allowsHitTesting(false)`. The player's
/// remote belongs to `PlayerInputSurface`, which only works because it has no focusable siblings at
/// rest — a Button up here would quietly take back the arrows and the touch-scrub with them.
struct AutoSyncBar: View {
    let banner: PlayerModel.AutoSyncBanner
    private static let trackWidth: CGFloat = 320

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .semibold))
            Text(banner.text)
                .font(.seret(24, .semibold))
            if let fraction = banner.fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.track)
                    Capsule().fill(Theme.Palette.focus)
                        // A floor, so the bar reads as started rather than as broken while the
                        // first seconds of audio are still arriving.
                        .frame(width: max(10, Self.trackWidth * fraction))
                }
                .frame(width: Self.trackWidth, height: 8)
                .animation(.easeOut(duration: 0.9), value: fraction)
            }
        }
        // White throughout, a failure included: the glyph says which it is. The app has no
        // amber or green accents any more.
        .foregroundStyle(Theme.Palette.textPrimary)
        .padding(.horizontal, 34).padding(.vertical, 20)
        .playerOverlaySurface(Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, PlayerLayout.topSlotInset)
        .allowsHitTesting(false)
    }

    private var glyph: String {
        switch banner.mood {
        case .measuring: "waveform"
        case .synced:    "checkmark.circle.fill"
        case .failed:    "exclamationmark.triangle.fill"
        }
    }
}

/// The surface every small player overlay sits on: the side sheet's dark panel gradient with a
/// hairline, so a bar over a bright frame reads like the rest of the chrome.
extension View {
    func playerOverlaySurface<S: InsettableShape>(_ shape: S) -> some View {
        background(LinearGradient(colors: [Theme.Palette.panelTop, Theme.Palette.panelBottom],
                                  startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1))
    }
}

/// "Up Next" bar near content-end. Seeds focus to "Play Now" so the remote acts on it; the
/// countdown auto-advances, and Menu (handled by the player) or Dismiss keeps watching.
struct UpNextBar: View {
    @Bindable var model: PlayerModel
    let next: Episode
    /// The scrub bar is up beneath: sit above it rather than over it.
    let clearsBar: Bool
    @FocusState private var playNowFocused: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("UP NEXT")
                            .font(.seret(.caption1, .semibold)).kerning(1.5)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        // A stall while Up Next is up. The bar's own spinner is out of reach here —
                        // the bar stays down so Up Next does not jump — so the hint rides in this
                        // line instead. Always laid out, only faded, so its arrival moves nothing.
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.Palette.textPrimary)
                            .opacity(model.isBuffering ? 1 : 0)
                            .accessibilityHidden(!model.isBuffering)
                    }
                    .animation(Theme.Anim.pageFade, value: model.isBuffering)
                    Text("S\(next.season) \u{2022} E\(next.number)  \u{00B7}  Playing in \(model.upNextSecondsRemaining)s")
                        .font(.seret(30, .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Spacer(minLength: 40)
                Button("Dismiss") { model.dismissUpNext() }
                    .buttonStyle(SeretActionButtonStyle())
                Button { model.playNextNow() } label: {
                    Label("Play Now", systemImage: "play.fill")
                }
                .buttonStyle(SeretActionButtonStyle(prominent: true))
                .focused($playNowFocused)
            }
            .padding(.horizontal, 40).padding(.vertical, 30)
            .playerOverlaySurface(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, PlayerLayout.sideInset)
            .padding(.bottom, clearsBar ? 130 : 20)
        }
        .animation(Theme.Anim.pageFade, value: clearsBar)
        .onAppear { playNowFocused = true }
    }
}

/// The paused state, in the middle of the frame: the pause glyph in a dark disc. Only while
/// nothing else is up — the row, the sheet and the strip all say where you are themselves.
struct PausedGlyph: View {
    var body: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: 60, weight: .bold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: 150, height: 150)
            .background(Theme.Palette.badgeBacking, in: Circle())
            .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .accessibilityLabel("Paused")
    }
}
