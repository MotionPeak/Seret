import SwiftUI

/// A title's description, clamped to a few lines — and, when that cut it short, a "MORE" you can
/// select to read the rest.
///
/// The overview used to be a bare `Text(…).lineLimit(4)`: a long description ended mid-word with
/// "…" and nothing on the page could show the remainder, because a plain text view is not
/// focusable on tvOS. The Apple TV app's answer is the one used here — the clamped text becomes a
/// focusable block, and selecting it opens the full description over the page; Menu closes it.
///
/// It is only focusable when something IS cut off. A focus stop that opens the same four lines
/// would be one more press on the way from the title to Play for nothing.
struct ExpandableOverview: View {
    let text: String
    /// Heads the full-text view, so it says whose description it is.
    let title: String
    var lineLimit = 4
    var maxWidth: CGFloat = 1100

    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0
    @State private var reading = false

    /// Measured, not guessed from a character count: line length depends on the font, the words
    /// and the width, and a wrong guess either hides the affordance or offers it for nothing.
    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        Button { reading = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).bodyText().lineLimit(lineLimit)
                    .background(height(into: $clampedHeight))
                if isTruncated {
                    Text("MORE")
                        .font(.seret(Theme.Typography.captionSize, .bold)).tracking(1.5)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .buttonStyle(OverviewButtonStyle())
        // Not a focus stop unless there is more to read. Settles once, at layout, before anyone
        // can have focused it — so this never disables a focused view under the viewer.
        .disabled(!isTruncated)
        // The same text unclamped and invisible, to learn how tall the whole of it is.
        .background(alignment: .topLeading) {
            Text(text).bodyText()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background(height(into: $fullHeight))
                .hidden()
        }
        .fullScreenCover(isPresented: $reading) {
            FullOverview(title: title, text: text)
        }
    }

    private func height(into binding: Binding<CGFloat>) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { binding.wrappedValue = proxy.size.height }
                .onChange(of: proxy.size.height) { _, h in binding.wrappedValue = h }
        }
    }
}

/// The clamped text on a soft platter when focused — it reads as text first, and only lights up
/// as a control when you land on it.
private struct OverviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Render(configuration: configuration) }

    private struct Render: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.12 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.goldBright.opacity(focused ? 0.9 : 0), lineWidth: 2))
                // Cancel the padding so the text stays aligned with the rest of the page at rest.
                .padding(.horizontal, -18).padding(.vertical, -12)
                .scaleEffect(focused ? 1.02 : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
    }
}

/// The whole description, centred over a dimmed page. Menu closes it (the cover's own dismissal).
private struct FullOverview: View {
    let title: String
    let text: String

    var body: some View {
        ZStack {
            // Blurred, then darkened: the page underneath stays a hint of where you were without
            // its own text competing with the description's.
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Rectangle().fill(.black.opacity(0.75)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Text(title).font(.seret(Theme.Typography.h2Size, .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                // A very long description steps down a size rather than running off the screen:
                // there is nothing focusable to scroll it with.
                ViewThatFits(in: .vertical) {
                    Text(text).bodyText().fixedSize(horizontal: false, vertical: true)
                    Text(text).font(.seret(Theme.Typography.calloutSize, .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text).font(.seret(Theme.Typography.captionSize, .regular))
                }
                .foregroundStyle(Theme.Palette.textPrimary)
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(60)
            // Something has to hold focus for the remote to have a target while this is up — but
            // not the system's lift, which would wobble a whole page of text.
            .focusable()
            .focusEffectDisabled()
        }
    }
}
