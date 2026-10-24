import AppKit
import DebridCore
import DebridUI
import SwiftUI

/// The sign-in card over the poster mosaic (approved mockup 6). Pure: it renders a
/// `SignInScreenState` and reports intents, so every state is previewable without a debrid account.
///
/// Two styles: `.window` is the signed-out main window (mosaic, brand, and — given
/// `switchProvider` — the Real-Debrid / TorBox choice); `.sheet` is Settings → Accounts' "Sign In…"
/// for one more account: the same panels, on the sheet's own background, with Cancel.
struct SignInScreen: View {
    enum Style { case window, sheet }

    let state: SignInScreenState
    @Binding var mode: SignInMode
    @Binding var token: String
    var posters: [URL] = []
    var style: Style = .window
    /// Draws the provider choice above the card when set (the signed-out screen only).
    var switchProvider: ((DebridProvider) -> Void)?
    var onRetry: () -> Void = {}
    var onSubmitToken: () -> Void = {}
    var onCancel: () -> Void = {}

    @Environment(\.openURL) private var openURL
    @Namespace private var modeSpace
    @State private var copied = false
    @State private var clock = SignInScreenState.CodeClock()

    private var copy: SignInScreenState.Copy { state.copy }

    var body: some View {
        Group {
            switch style {
            case .window:
                ZStack {
                    PosterMosaic(urls: posters).ignoresSafeArea()
                    RadialGradient(colors: [Theme.Palette.gold.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.06),
                                   startRadius: 0, endRadius: 520).ignoresSafeArea()
                    card
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 50, y: 24)
                }
                .frame(minWidth: 1000, minHeight: 650)
            case .sheet:
                card
            }
        }
        .animation(Theme.Motion.standard, value: state)
        .animation(Theme.Motion.standard, value: mode)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            if let switchProvider { providerPicker(switchProvider).padding(.bottom, 16) }
            if !isFailure { modePicker.padding(.bottom, 22) }
            panel.transition(.opacity.combined(with: .offset(y: 8)))
            if style == .sheet {
                Button("Cancel", action: onCancel)
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 24)
            }
        }
        .padding(.horizontal, 38).padding(.vertical, 34)
        .frame(width: 480)
    }

    @ViewBuilder private var header: some View {
        switch style {
        case .window:
            SeretMark().frame(width: 58).padding(.bottom, 12)
            Wordmark(hebrewSize: 46)
            Text("Your debrid library, everywhere.")
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0xC9C9CE))
                .padding(.top, 10).padding(.bottom, 22)
        case .sheet:
            SeretMark().frame(width: 40).padding(.bottom, 12)
            Text("Sign in to \(state.provider.displayName)")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
            Text("Its titles join your library next to the ones you already have.")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0xC9C9CE))
                .multilineTextAlignment(.center)
                .padding(.top, 6).padding(.bottom, 22)
        }
    }

    private var isFailure: Bool { if case .failed = state.panel { true } else { false } }

    /// Which account to sign in to. The selection IS the model on screen: a pick asks the session
    /// for that provider's model, and the picker follows the one it hands back.
    private func providerPicker(_ switchProvider: @escaping (DebridProvider) -> Void) -> some View {
        Picker("Service", selection: Binding(get: { state.provider }, set: { switchProvider($0) })) {
            ForEach(DebridProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(width: 260)
        .accessibilityLabel("Debrid service")
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton("Sign in with a code", .code)
            modeButton(copy.tokenMode, .token)
        }
        .padding(4)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
    }

    private func modeButton(_ title: String, _ value: SignInMode) -> some View {
        Button { withAnimation(Theme.Motion.standard) { mode = value } } label: {
            Text(title).font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(mode == value ? Theme.Palette.onGold : Color(hex: 0x9A9AA0))
                .padding(.vertical, 6).padding(.horizontal, 16)
                .background {
                    if mode == value {
                        Capsule().fill(Theme.Palette.goldGradient).goldGlow(10, opacity: 0.4)
                            .matchedGeometryEffect(id: "mode", in: modeSpace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var panel: some View {
        switch state.panel {
        case .preparing(let label):
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(Theme.Palette.gold)
                Text(label).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(height: 150)
        case .code(let userCode, let url, let expiresIn):
            codePanel(userCode: userCode, url: url, expiresIn: expiresIn)
        case .token(let checking, let error):
            tokenPanel(checking: checking, error: error)
        case .failed(let message):
            failurePanel(message)
        }
    }

    private static let codeActionFont = Font.system(size: 13, weight: .bold)

    private func codePanel(userCode: String, url: URL?, expiresIn: Int) -> some View {
        let page = copy.codePage(for: url)
        return VStack(spacing: 0) {
            // Interpolated, not `Text + Text`: that operator is deprecated in the macOS 26 SDK.
            Text("Enter this code at \(Text(page).bold().foregroundStyle(Theme.Palette.textPrimary))")
                .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xC9C9CE))
            Text(SignInScreenState.formatUserCode(userCode))
                .font(.system(size: 42, weight: .heavy, design: .monospaced)).tracking(4)
                .foregroundStyle(Theme.Palette.gold).goldGlow(14, opacity: 0.45)
                .textSelection(.enabled)
                .padding(.top, 6).padding(.bottom, 20)
            HStack(spacing: 10) {
                // One line each, at the mockup's smaller size: at the style's headline size the pair
                // is wider than the card and the gold button wrapped onto two lines.
                Button { if let url { openURL(url) } } label: {
                    Label("Open \(page)", systemImage: "arrow.up.right.square")
                        .font(Self.codeActionFont).lineLimit(1).fixedSize()
                }
                .buttonStyle(GoldButtonStyle())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Self.codeActionFont).lineLimit(1).fixedSize()
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.bottom, 20)
            TimelineView(.periodic(from: clock.shownAt, by: 1)) { context in
                let left = clock.secondsLeft(expiresIn: expiresIn, at: context.date)
                HStack(spacing: 8) {
                    // `symbolEffect` only animates SF Symbols; a plain dot breathes via phaseAnimator.
                    Circle().fill(Theme.Palette.gold).frame(width: 7, height: 7)
                        .shadow(color: Theme.Palette.gold, radius: 5)
                        .phaseAnimator([false, true]) { dot, bright in
                            dot.opacity(bright ? 1 : 0.35).scaleEffect(bright ? 1.15 : 0.8)
                        } animation: { _ in .easeInOut(duration: 0.7) }
                    Text("Waiting for you to approve · expires in \(SignInScreenState.countdown(secondsLeft: left))")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .onChange(of: userCode, initial: true) { clock.show(userCode, at: Date()) }
    }

    private func tokenPanel(checking: Bool, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SecureField(copy.tokenPlaceholder, text: $token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .onSubmit(onSubmitToken)
                Button("Paste ⌘V") {
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .controlSize(.small)
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
            if let error {
                Text(error).font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xFF9F43))
            }
            HStack(spacing: 4) {
                Text("Find it at").foregroundStyle(Theme.Palette.textSecondary)
                Link(copy.tokenPage, destination: copy.tokenPageURL)
                    .foregroundStyle(Theme.Palette.gold)
                Text("· it skips the code step entirely.").foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(.system(size: 12))
            Button(action: onSubmitToken) {
                HStack(spacing: 8) {
                    if checking { ProgressView().controlSize(.small).tint(Theme.Palette.onGold) }
                    Text(checking ? "Checking…" : "Sign In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
            .padding(.top, 6)
        }
    }

    private func failurePanel(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(Theme.Palette.gold)
            Text(message).font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xC9C9CE))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Try Again", action: onRetry).buttonStyle(GoldButtonStyle())
                Button(copy.tokenFailureAction) { withAnimation(Theme.Motion.standard) { mode = .token } }
                    .buttonStyle(GlassButtonStyle())
            }
        }
    }
}
