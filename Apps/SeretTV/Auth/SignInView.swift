import DebridCore
import DebridUI
import SwiftUI

/// The sign-in screen for one debrid provider. Default: device-code. Secondary: paste a personal
/// API token (Real-Debrid: real-debrid.com/apitoken, which bypasses RD's throttled device-code
/// endpoint) or a TorBox API key (torbox.app/settings).
///
/// Two hosts: the signed-out screen, which passes `onSwitchProvider` and so shows the
/// "Real-Debrid / TorBox" choice, and Settings → Accounts' add-an-account page, which signs in to
/// one provider and names it instead.
struct SignInView: View {
    let model: SignInModel
    /// The provider choice. Nil on a page that signs in to `model.provider` only.
    var onSwitchProvider: ((DebridProvider) -> Void)? = nil

    var body: some View {
        SignInContent(phase: model.phase, provider: model.provider,
                      onSwitchProvider: onSwitchProvider,
                      onRetry: { model.retry() },
                      onSubmitToken: { token in Task { await model.signInWithToken(token) } })
            // Keyed on the model's identity too: the provider choice hands this view a different
            // model, and both start at attempt 0.
            .task(id: model.taskKey) { await model.run() }
    }
}

/// What the sign-in screen draws for a phase — split from `SignInView` so the `-uiPreview signin`
/// harnesses can show each state without a model (whose flow is the real, throttled endpoint).
struct SignInContent: View {
    let phase: SignInModel.Phase
    let provider: DebridProvider
    let onSwitchProvider: ((DebridProvider) -> Void)?
    let onRetry: () -> Void
    let onSubmitToken: (String) -> Void
    @State private var showingTokenEntry: Bool
    /// Never prefilled, never shown (a SecureField), never logged — it only travels to `onSubmitToken`.
    @State private var tokenText = ""
    @FocusState private var focus: Focus?

    private enum Focus: Hashable {
        case provider(DebridProvider)
        case tokenField
        case retry
    }

    init(phase: SignInModel.Phase, provider: DebridProvider = .realDebrid,
         onSwitchProvider: ((DebridProvider) -> Void)? = nil,
         showingTokenEntry: Bool = false,
         onRetry: @escaping () -> Void, onSubmitToken: @escaping (String) -> Void) {
        self.phase = phase
        self.provider = provider
        self.onSwitchProvider = onSwitchProvider
        self.onRetry = onRetry
        self.onSubmitToken = onSubmitToken
        _showingTokenEntry = State(initialValue: showingTokenEntry)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            if showingTokenEntry {
                tokenEntry
            } else {
                switch phase {
                case .idle, .requestingCode:
                    SeretLoader(label: "Preparing sign‑in…")
                case .awaitingAuthorization(let code):
                    deviceCode(code)
                case .validatingToken:
                    SeretLoader(label: copy.checking)
                case .signedIn:
                    SeretLoader(label: "Signing in…")
                case .failed(let message):
                    failure(message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Outside the switch, so the choice keeps its identity (and focus) through every phase.
        .overlay(alignment: .top) { header.padding(.top, 50) }
        // Where focus goes when the screen opens AND when the focused control vanishes (a phase
        // change, the key form opening or closing): the state's own control, never whichever pill
        // happens to sit first. Without the choice above, the code screen's one button is the
        // system's pick anyway.
        .defaultFocus($focus, defaultFocus)
        // A key typed for one provider must never be submitted to the other.
        .onChange(of: provider) { _, _ in
            tokenText = ""
            showingTokenEntry = false
        }
    }

    private var defaultFocus: Focus {
        if showingTokenEntry { return .tokenField }
        if case .failed = phase { return .retry }
        return .provider(provider)
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        if let onSwitchProvider {
            // Press to choose, never "switch on focus": each switch stops one flow and starts
            // another, and a focus glide across the row would fire both.
            HStack(spacing: 20) {
                ForEach(DebridProvider.allCases, id: \.self) { option in
                    Button(option.displayName) {
                        guard option != provider else { return }
                        onSwitchProvider(option)
                    }
                    .buttonStyle(SeretPillStyle(selected: option == provider))
                    .focused($focus, equals: .provider(option))
                }
            }
            .focusSection()
        } else {
            Text("Sign in to \(provider.displayName)")
                .sectionTitle()
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    // MARK: - States

    private func deviceCode(_ code: RDDeviceCode) -> some View {
        VStack(spacing: 56) {
            Wordmark(hebrewSize: 64)
            HStack(alignment: .center, spacing: 80) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("On your phone or computer, go to")
                        .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                    Text(Self.displayURL(code.verificationURL, keepsQuery: provider == .realDebrid))
                        .screenTitle().foregroundStyle(Theme.Palette.textPrimary)
                    Text("and enter this code:")
                        .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.top, 6)
                    Text(code.userCode)
                        .font(.system(size: 96, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                if let qr = QRCode.image(from: Self.scannableURL(code.verificationURL)) {
                    qr.resizable().interpolation(.none).scaledToFit()
                        .frame(width: 300, height: 300).padding(20)
                        // White is the QR's own ground, not chrome: a scanner needs the contrast.
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            VStack(spacing: 28) {
                Label("Waiting for authorization…", systemImage: "hourglass")
                    .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                Button(copy.useToken) { showingTokenEntry = true }
                    .buttonStyle(SeretActionButtonStyle())
            }
        }
        .padding(80)
    }

    private var tokenEntry: some View {
        VStack(spacing: 28) {
            Text(copy.tokenTitle).screenTitle().foregroundStyle(Theme.Palette.textPrimary)
            Text(copy.tokenHint)
                .calloutText().foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            SecureField(copy.tokenPlaceholder, text: $tokenText)
                .textContentType(.password)
                .focused($focus, equals: .tokenField)
                .frame(maxWidth: 700)
            if case .validatingToken = phase { ProgressView().tint(Theme.Palette.textPrimary) }
            if case .failed(let message) = phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .calloutText().foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center).frame(maxWidth: 700)
            }
            HStack(spacing: 24) {
                Button("Sign In") { onSubmitToken(tokenText) }
                    .buttonStyle(SeretActionButtonStyle(prominent: true))
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Use a code instead") { showingTokenEntry = false }
                    .buttonStyle(SeretActionButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(80)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 32) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(Theme.Palette.textSecondary)
            Text(message).sectionTitle().foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center).frame(maxWidth: 800)
            HStack(spacing: 24) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(SeretActionButtonStyle(prominent: true))
                    .focused($focus, equals: .retry)
                Button(copy.useToken) { showingTokenEntry = true }
                    .buttonStyle(SeretActionButtonStyle())
            }
        }
        .padding(80)
    }

    // MARK: - Copy

    private struct Copy {
        let useToken: String
        let tokenTitle: String
        let tokenHint: String
        let tokenPlaceholder: String
        let checking: String
    }

    private var copy: Copy {
        switch provider {
        case .realDebrid:
            Copy(useToken: "Use a Real‑Debrid token instead",
                 tokenTitle: "Sign in with a token",
                 tokenHint: "Get your token at real‑debrid.com/apitoken, then paste it here.",
                 tokenPlaceholder: "Real‑Debrid API token",
                 checking: "Checking token…")
        case .torBox:
            Copy(useToken: "Use a TorBox API key instead",
                 tokenTitle: "Sign in with an API key",
                 tokenHint: "Get your API key at torbox.app/settings, then paste it here.",
                 tokenPlaceholder: "TorBox API key",
                 checking: "Checking key…")
        }
    }

    // MARK: - URLs

    /// "https://real-debrid.com/device" → "real-debrid.com/device". TorBox's friendly URL carries
    /// the code in its query, which the screen already shows in large type, so it is dropped there
    /// (`keepsQuery: false`) — the viewer reads "tor.box/link".
    static func displayURL(_ raw: String, keepsQuery: Bool) -> String {
        guard let comps = URLComponents(string: scannableURL(raw)), let host = comps.host else { return raw }
        let query = keepsQuery ? (comps.query.map { "?\($0)" } ?? "") : ""
        return host + comps.path + query
    }

    /// TorBox can hand out its friendly URL without a scheme ("torbox.app/link?code=…"); a phone's
    /// camera only opens a QR as a link when it has one.
    static func scannableURL(_ raw: String) -> String {
        raw.contains("://") ? raw : "https://" + raw
    }
}
