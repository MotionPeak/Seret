import AppKit
import DebridUI
import SwiftUI

/// The sign-in card over the poster mosaic (approved mockup 6). Pure: it renders a
/// `SignInScreenState` and reports intents, so every state is previewable without Real-Debrid.
struct SignInScreen: View {
    let state: SignInScreenState
    @Binding var mode: SignInMode
    @Binding var token: String
    var posters: [URL] = []
    var onRetry: () -> Void = {}
    var onSubmitToken: () -> Void = {}

    @Environment(\.openURL) private var openURL
    @Namespace private var modeSpace
    @State private var copied = false
    @State private var codeShownAt = Date()

    var body: some View {
        ZStack {
            PosterMosaic(urls: posters).ignoresSafeArea()
            RadialGradient(colors: [Theme.Palette.gold.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.06),
                           startRadius: 0, endRadius: 520).ignoresSafeArea()
            card
        }
        .frame(minWidth: 1000, minHeight: 650)
        .animation(Theme.Motion.standard, value: state)
        .animation(Theme.Motion.standard, value: mode)
    }

    private var card: some View {
        VStack(spacing: 0) {
            SeretMark().frame(width: 58).padding(.bottom, 12)
            Wordmark(hebrewSize: 46)
            Text("Your debrid library, everywhere.")
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0xC9C9CE))
                .padding(.top, 10).padding(.bottom, 22)
            if !isFailure { modePicker.padding(.bottom, 22) }
            panel.transition(.opacity.combined(with: .offset(y: 8)))
        }
        .padding(.horizontal, 38).padding(.vertical, 34)
        .frame(width: 480)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 50, y: 24)
    }

    private var isFailure: Bool { if case .failed = state.panel { true } else { false } }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton("Sign in with a code", .code)
            modeButton("Use a token", .token)
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

    private func codePanel(userCode: String, url: URL?, expiresIn: Int) -> some View {
        VStack(spacing: 0) {
            // Interpolated, not `Text + Text`: that operator is deprecated in the macOS 26 SDK.
            Text("Enter this code at \(Text("real-debrid.com/device").bold().foregroundStyle(Theme.Palette.textPrimary))")
                .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xC9C9CE))
            Text(SignInScreenState.formatUserCode(userCode))
                .font(.system(size: 42, weight: .heavy, design: .monospaced)).tracking(4)
                .foregroundStyle(Theme.Palette.gold).goldGlow(14, opacity: 0.45)
                .textSelection(.enabled)
                .padding(.top, 6).padding(.bottom, 20)
            HStack(spacing: 10) {
                Button { if let url { openURL(url) } } label: {
                    Label("Open real-debrid.com/device", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(GoldButtonStyle())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.bottom, 20)
            TimelineView(.periodic(from: codeShownAt, by: 1)) { context in
                let left = expiresIn - Int(context.date.timeIntervalSince(codeShownAt))
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
        .onChange(of: userCode, initial: true) { codeShownAt = Date() }
    }

    private func tokenPanel(checking: Bool, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SecureField("Paste your Real-Debrid API token", text: $token)
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
                Link("real-debrid.com/apitoken", destination: URL(string: "https://real-debrid.com/apitoken")!)
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
                Button("Use a Token") { withAnimation(Theme.Motion.standard) { mode = .token } }
                    .buttonStyle(GlassButtonStyle())
            }
        }
    }
}
