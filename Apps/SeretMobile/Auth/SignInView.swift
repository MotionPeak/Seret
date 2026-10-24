import DebridCore
import DebridUI
import SwiftUI

/// Touch sign-in, on the glass language. Default: device-code — show the code and open Real‑Debrid
/// in an in-app browser. Fallback: paste a personal API token (the durable path past the throttle).
///
/// The sign-in itself is `SignInModel`'s and is unchanged; this view only maps its phase onto
/// `SignInCard` (split out so the DEBUG harness can draw every face without a network).
struct SignInView: View {
    let model: SignInModel
    @State private var showingTokenEntry = false
    @State private var tokenText = ""
    @State private var presentedURL: PresentedURL?

    var body: some View {
        SignInCard(face: face, tokenText: $tokenText,
                   openVerification: { url in presentedURL = PresentedURL(url: url) },
                   useToken: { showingTokenEntry = true },
                   back: { showingTokenEntry = false },
                   submitToken: { Task { await model.signInWithToken(tokenText) } },
                   retry: { model.retry() })
            .task(id: model.taskKey) { await model.run() }
            .sheet(item: $presentedURL) { SafariSheet(url: $0.url) }
    }

    private var face: SignInCard.Face {
        if showingTokenEntry {
            let checking: Bool = { if case .validatingToken = model.phase { return true }; return false }()
            let error: String? = { if case .failed(let message) = model.phase { return message }; return nil }()
            return .token(checking: checking, error: error)
        }
        switch model.phase {
        case .idle, .requestingCode: return .preparing("Preparing sign\u{2011}in…")
        case .awaitingAuthorization(let code): return .code(code.userCode, URL(string: code.verificationURL))
        case .validatingToken: return .preparing("Checking token…")
        case .signedIn: return .preparing("Signing in…")
        case .failed(let message): return .failed(message)
        }
    }
}

/// The sign-in page itself: the wordmark over a soft white bloom, then one glass card holding
/// whatever the sign-in is doing.
struct SignInCard: View {
    enum Face: Equatable {
        case preparing(String)
        case code(String, URL?)
        case token(checking: Bool, error: String?)
        case failed(String)
    }

    let face: Face
    @Binding var tokenText: String
    let openVerification: (URL) -> Void
    let useToken: () -> Void
    let back: () -> Void
    let submitToken: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            CanvasBackground()
            RadialGradient(colors: [Color.white.opacity(0.07), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    SeretMark(glow: false).frame(width: 56).padding(.top, 56)
                    Wordmark(hebrewSize: 52)
                    Text("Your debrid library, everywhere.")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    card
                        .padding(.top, Theme.Space.lg)
                }
                .frame(maxWidth: 440).frame(maxWidth: .infinity)
                .padding(Theme.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(Theme.Motion.standard, value: face)
    }

    private var card: some View {
        Group {
            switch face {
            case .preparing(let label): preparing(label)
            case .code(let code, let url): deviceCode(code, url: url)
            case .token(let checking, let error): tokenEntry(checking: checking, error: error)
            case .failed(let message): failure(message)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity)
        .seretGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous),
                    interactive: false)
    }

    private func preparing(_ label: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView().tint(Theme.Palette.focus)
            Text(label).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(minHeight: 120)
    }

    private func deviceCode(_ code: String, url: URL?) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Enter this code at Real\u{2011}Debrid")
                .font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text(code)
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Theme.Palette.textPrimary)
                .textSelection(.enabled)
                .padding(.vertical, Theme.Space.sm).padding(.horizontal, Theme.Space.xl)
                .background(Theme.Palette.glassFaint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
            Button {
                if let url { openVerification(url) }
            } label: {
                Label("Open Real\u{2011}Debrid", systemImage: "safari")
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small).tint(Theme.Palette.textTertiary)
                Text("Waiting for authorization…")
            }
            .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textTertiary)
            Button("Use a Real\u{2011}Debrid token instead", action: useToken)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private func tokenEntry(checking: Bool, error: String?) -> some View {
        VStack(spacing: Theme.Space.lg) {
            VStack(spacing: Theme.Space.xs) {
                Text("Paste your token").font(Theme.Typo.title()).foregroundStyle(Theme.Palette.textPrimary)
                Text("Get it at real\u{2011}debrid.com/apitoken")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            // Labelled, like every field: the name stays above it once something is pasted.
            GlassField(label: "Real\u{2011}Debrid API token", text: $tokenText, prompt: "Paste token",
                       secure: true, contentType: .password)
                .background(Theme.Palette.glassFaint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if checking { ProgressView().tint(Theme.Palette.focus) }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.destructive)
                    .multilineTextAlignment(.center)
            }
            Button(action: submitToken) { Text("Sign In") }
                .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
                .disabled(tokenText.isEmpty)
            Button("Back", action: back)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(Theme.Palette.textSecondary)
            Text(message).multilineTextAlignment(.center)
                .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
            VStack(spacing: Theme.Space.md) {
                Button(action: retry) { Text("Try Again") }
                    .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
                Button("Use a token", action: useToken).buttonStyle(GlassPillButtonStyle())
            }
        }
    }
}
