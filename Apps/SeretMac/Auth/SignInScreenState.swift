import DebridCore
import DebridUI
import Foundation

enum SignInMode: Equatable { case code, token }

/// What the sign-in card shows, derived from the shared `SignInModel` phase and the viewer's chosen
/// mode. Pure, so every state can be tested and previewed without Real-Debrid.
struct SignInScreenState: Equatable {
    enum Panel: Equatable {
        case preparing(String)
        case code(userCode: String, verificationURL: URL?, expiresIn: Int)
        case token(checking: Bool, error: String?)
        case failed(String)
    }

    var panel: Panel

    static func make(phase: SignInModel.Phase, mode: SignInMode) -> SignInScreenState {
        if phase == .signedIn { return .init(panel: .preparing("Signing in…")) }
        switch mode {
        case .token:
            switch phase {
            case .validatingToken: return .init(panel: .token(checking: true, error: nil))
            case .failed(let message): return .init(panel: .token(checking: false, error: message))
            default: return .init(panel: .token(checking: false, error: nil))
            }
        case .code:
            switch phase {
            case .awaitingAuthorization(let code):
                return .init(panel: .code(userCode: code.userCode, verificationURL: URL(string: code.verificationURL),
                                          expiresIn: code.expiresIn))
            case .failed(let message): return .init(panel: .failed(message))
            case .validatingToken: return .init(panel: .preparing("Checking token…"))
            default: return .init(panel: .preparing("Preparing sign-in…"))
            }
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

    static func countdown(secondsLeft: Int) -> String {
        let seconds = max(0, secondsLeft)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
