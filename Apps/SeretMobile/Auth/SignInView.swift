import DebridCore
import DebridUI
import SwiftUI

/// Touch sign-in, on the glass language, for either debrid account. Default: device-code — show the
/// code and open the provider's link page in an in-app browser. Fallback: paste a personal API
/// token / key (Real‑Debrid's durable path past its device-code throttle).
///
/// The sign-in itself is `SignInModel`'s; this view only maps its phase onto `SignInCard` (split out
/// so the DEBUG harness can draw every face without a network). The same view serves the signed-out
/// screen (with the provider picker) and Settings → Accounts' "Sign In" sheet (without it).
struct SignInView: View {
    let model: SignInModel
    /// The signed-out screen's Real‑Debrid / TorBox choice (`AppSession.switchSignIn(to:)`). Nil when
    /// the provider is fixed — adding a second account from Settings.
    var switchProvider: ((DebridProvider) -> Void)?
    @State private var showingTokenEntry = false
    @State private var tokenText = ""
    @State private var presentedURL: PresentedURL?

    var body: some View {
        SignInCard(provider: model.provider, face: face, tokenText: $tokenText,
                   switchProvider: switchProvider,
                   openVerification: { url in presentedURL = PresentedURL(url: url) },
                   useToken: { showingTokenEntry = true },
                   back: { showingTokenEntry = false },
                   submitToken: { Task { await model.signInWithToken(tokenText) } },
                   retry: { model.retry() })
            .task(id: model.taskKey) { await model.run() }
            // A different model is a different sign-in (the picker switched provider): nothing typed
            // for one provider may carry over to the other — least of all a pasted key.
            .onChange(of: ObjectIdentifier(model)) { _, _ in
                showingTokenEntry = false
                tokenText = ""
                presentedURL = nil
            }
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
        case .awaitingAuthorization(let code):
            return .code(code.userCode, SignInCard.verificationURL(code.verificationURL))
        case .validatingToken:
            return .preparing(model.provider == .torBox ? "Checking key…" : "Checking token…")
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

    let provider: DebridProvider
    let face: Face
    @Binding var tokenText: String
    /// Draws the Real‑Debrid / TorBox picker above the card when set.
    var switchProvider: ((DebridProvider) -> Void)?
    let openVerification: (URL) -> Void
    let useToken: () -> Void
    let back: () -> Void
    let submitToken: () -> Void
    let retry: () -> Void

    /// The device-code page as a URL Safari can open. TorBox hands back a "friendly" address that
    /// may come without a scheme (`tor.box/link`), and `SFSafariViewController` traps on anything
    /// that isn't http(s) — so a bare host gets `https://`, and anything else opens nothing.
    static func verificationURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return url
    }

    /// Every provider-specific word on the page. Real‑Debrid's are the ones it always had.
    private struct Copy {
        let codeHeading: String
        let tokenSwitch: String
        let tokenShort: String
        let tokenTitle: String
        let tokenWhere: String
        let tokenField: String
        let tokenPrompt: String
    }

    private var copy: Copy {
        switch provider {
        case .realDebrid:
            Copy(codeHeading: "Enter this code at Real\u{2011}Debrid",
                 tokenSwitch: "Use a Real\u{2011}Debrid token instead",
                 tokenShort: "Use a token",
                 tokenTitle: "Paste your token",
                 tokenWhere: "Get it at real\u{2011}debrid.com/apitoken",
                 tokenField: "Real\u{2011}Debrid API token",
                 tokenPrompt: "Paste token")
        case .torBox:
            Copy(codeHeading: "Enter this code at TorBox",
                 tokenSwitch: "Use a TorBox API key instead",
                 tokenShort: "Use an API key",
                 tokenTitle: "Paste your API key",
                 tokenWhere: "Get it at torbox.app/settings",
                 tokenField: "TorBox API key",
                 tokenPrompt: "Paste key")
        }
    }

    /// The open-the-page button: Real‑Debrid's by name, TorBox's by the address it shows
    /// (`tor.box/link`) so the viewer can type it on another device too.
    private func openLabel(_ url: URL?) -> String {
        switch provider {
        case .realDebrid: return "Open Real\u{2011}Debrid"
        case .torBox:
            guard let url, let host = url.host else { return "Open TorBox" }
            let path = url.path == "/" ? "" : url.path
            return "Open \(host)\(path)"
        }
    }

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
                    if let switchProvider {
                        providerPicker(switchProvider)
                            .padding(.top, Theme.Space.lg)
                    }
                    card
                        .padding(.top, switchProvider == nil ? Theme.Space.lg : 0)
                }
                .frame(maxWidth: 440).frame(maxWidth: .infinity)
                .padding(Theme.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(Theme.Motion.standard, value: face)
    }

    /// Which account to sign in to. The selection IS the model on screen: a pick asks the session
    /// for that provider's model, and the picker follows the one it hands back.
    private func providerPicker(_ switchProvider: @escaping (DebridProvider) -> Void) -> some View {
        Picker("Service", selection: Binding(get: { provider }, set: { switchProvider($0) })) {
            ForEach(DebridProvider.allCases, id: \.self) { Text($0.uiName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Debrid service")
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
            Text(copy.codeHeading)
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
                Label(openLabel(url), systemImage: "safari")
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small).tint(Theme.Palette.textTertiary)
                Text("Waiting for authorization…")
            }
            .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textTertiary)
            Button(copy.tokenSwitch, action: useToken)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private func tokenEntry(checking: Bool, error: String?) -> some View {
        VStack(spacing: Theme.Space.lg) {
            VStack(spacing: Theme.Space.xs) {
                Text(copy.tokenTitle).font(Theme.Typo.title()).foregroundStyle(Theme.Palette.textPrimary)
                Text(copy.tokenWhere)
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            // Labelled, like every field: the name stays above it once something is pasted.
            GlassField(label: copy.tokenField, text: $tokenText, prompt: copy.tokenPrompt,
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
                Button(copy.tokenShort, action: useToken).buttonStyle(GlassPillButtonStyle())
            }
        }
    }
}
