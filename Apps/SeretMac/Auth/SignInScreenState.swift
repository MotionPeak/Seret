import DebridCore
import DebridUI
import Foundation

enum SignInMode: Equatable { case code, token }

/// What the sign-in card shows, derived from the shared `SignInModel` phase, its provider and the
/// viewer's chosen mode. Pure, so every state can be tested and previewed without a debrid account.
struct SignInScreenState: Equatable {
    enum Panel: Equatable {
        case preparing(String)
        case code(userCode: String, verificationURL: URL?, expiresIn: Int)
        case token(checking: Bool, error: String?)
        case failed(String)
    }

    /// Which account this card signs in to. Every provider-specific word comes from it (`copy`).
    var provider: DebridProvider = .realDebrid
    var panel: Panel

    var copy: Copy { Copy(provider: provider) }

    /// `tokenSubmitted`: whether the viewer has pressed Sign In on the token panel since opening it.
    /// The model has ONE `failed` phase for both routes, and the code route keeps running behind the
    /// token panel — so without this, "Real-Debrid is busy" (the very error that offers *Use a Token*)
    /// or an expired code would greet the viewer under the token field as if their token were wrong.
    static func make(phase: SignInModel.Phase, mode: SignInMode, tokenSubmitted: Bool = false,
                     provider: DebridProvider = .realDebrid) -> SignInScreenState {
        .init(provider: provider, panel: panel(phase: phase, mode: mode, tokenSubmitted: tokenSubmitted,
                                               copy: Copy(provider: provider)))
    }

    private static func panel(phase: SignInModel.Phase, mode: SignInMode, tokenSubmitted: Bool, copy: Copy) -> Panel {
        if phase == .signedIn { return .preparing("Signing in…") }
        switch mode {
        case .token:
            switch phase {
            case .validatingToken: return .token(checking: true, error: nil)
            case .failed(let message): return .token(checking: false, error: tokenSubmitted ? message : nil)
            default: return .token(checking: false, error: nil)
            }
        case .code:
            switch phase {
            case .awaitingAuthorization(let code):
                return .code(userCode: code.userCode, verificationURL: verificationURL(code.verificationURL),
                             expiresIn: code.expiresIn)
            case .failed(let message): return .failed(message)
            case .validatingToken: return .preparing(copy.checking)
            default: return .preparing("Preparing sign-in…")
            }
        }
    }

    /// The device-code page as a URL a browser can open. TorBox hands back a "friendly" address that
    /// may come without a scheme (`tor.box/link`): a bare host gets `https://`, and anything that is
    /// not http(s) opens nothing.
    static func verificationURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return url
    }

    /// Every provider-specific word on the card. Real-Debrid's are the ones it always had.
    struct Copy: Equatable {
        let provider: DebridProvider
        /// The mode picker's second choice.
        let tokenMode: String
        /// The failure panel's way out to the token field.
        let tokenFailureAction: String
        let tokenPlaceholder: String
        /// Where the token / key is found, as shown and as opened.
        let tokenPage: String
        let tokenPageURL: URL
        /// The code panel while a pasted token / key is being checked.
        let checking: String

        init(provider: DebridProvider) {
            self.provider = provider
            switch provider {
            case .realDebrid:
                tokenMode = "Use a token"
                tokenFailureAction = "Use a Token"
                tokenPlaceholder = "Paste your Real-Debrid API token"
                tokenPage = "real-debrid.com/apitoken"
                tokenPageURL = URL(string: "https://real-debrid.com/apitoken")!
                checking = "Checking token…"
            case .torBox:
                tokenMode = "Use an API key"
                tokenFailureAction = "Use an API Key"
                tokenPlaceholder = "Paste your TorBox API key"
                tokenPage = "torbox.app/settings"
                tokenPageURL = URL(string: "https://torbox.app/settings")!
                checking = "Checking key…"
            }
        }

        /// The address the code is entered at, as the card writes it. Real-Debrid's is the one it
        /// always showed; TorBox's is the page it sent (`tor.box/link`), so it can be typed on
        /// another device too.
        func codePage(for url: URL?) -> String {
            switch provider {
            case .realDebrid:
                return "real-debrid.com/device"
            case .torBox:
                guard let url, let host = url.host else { return "torbox.app" }
                let path = url.path == "/" ? "" : url.path
                return host + path
            }
        }
    }

    /// What the viewer has typed and chosen on the card — kept together so a different sign-in (the
    /// provider picker swapped the model) can drop all of it at once. Never logged or shown back.
    struct Entry: Equatable {
        private(set) var provider: DebridProvider
        var mode: SignInMode = .code
        var token = ""
        /// Set by Sign In on the token panel, cleared by any change of panel: only then is a failure
        /// the token's own (see `make`).
        var tokenSubmitted = false

        init(provider: DebridProvider) { self.provider = provider }

        /// A different sign-in: nothing typed for one provider may carry over to the other — least
        /// of all a pasted key — and the card starts again on the code.
        mutating func switchProvider(to provider: DebridProvider) {
            self = Entry(provider: provider)
        }

        /// The token to check, once: nil when nothing is typed or a check is already running (Return
        /// in the field bypasses the button's disabled state).
        mutating func submit(phase: SignInModel.Phase) -> String? {
            guard phase != .validatingToken,
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            tokenSubmitted = true
            return token
        }
    }

    /// "W6XD2P7N" → "W6XD 2P7N": easier to read across to a browser. Codes that are not plain letters
    /// and digits are shown exactly as Real-Debrid sent them.
    static func formatUserCode(_ code: String) -> String {
        guard code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return code }
        let characters = Array(code)
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: " ")
    }

    /// When the code on screen was first shown. The model reuses an unexpired code on Try Again, and
    /// the code outlives a visit to the token panel, so the clock restarts only for a NEW code —
    /// restarting it whenever the panel reappeared showed a fresh ten minutes for an old code.
    struct CodeClock: Equatable {
        private(set) var code: String?
        private(set) var shownAt: Date = .distantPast

        mutating func show(_ code: String, at now: Date) {
            guard code != self.code else { return }
            self.code = code
            shownAt = now
        }

        func secondsLeft(expiresIn: Int, at now: Date) -> Int {
            expiresIn - Int(now.timeIntervalSince(shownAt))
        }
    }

    static func countdown(secondsLeft: Int) -> String {
        let seconds = max(0, secondsLeft)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
