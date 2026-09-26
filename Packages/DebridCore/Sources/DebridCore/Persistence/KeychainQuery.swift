#if canImport(Security)
import Foundation
import Security

/// The one place a Keychain query is built, so every store follows the same platform rules.
///
/// On macOS a generic-password item goes to the legacy file keychain unless the query opts into the
/// data-protection keychain, and the file keychain ignores `…ThisDeviceOnly`. So macOS asks for the
/// data-protection keychain, which behaves like iOS. That keychain requires the app to be signed with
/// an application identifier. A locally signed development build is not, gets
/// `errSecMissingEntitlement`, and falls back to the file keychain rather than losing its sign-in.
enum KeychainQuery {
    static func base(service: String, account: String,
                     dataProtection: Bool = prefersDataProtection) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    /// iOS and tvOS only have the data-protection keychain; macOS must ask for it.
    static var prefersDataProtection: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// The call failed only because this build is not entitled to the data-protection keychain.
    static func shouldFallBackToLegacy(_ status: OSStatus) -> Bool {
        prefersDataProtection && status == errSecMissingEntitlement
    }

    /// Runs `operation` against the preferred keychain, and once more against the legacy file
    /// keychain when this build is not entitled to the preferred one.
    static func perform(service: String, account: String,
                        _ operation: ([String: Any]) -> OSStatus) -> OSStatus {
        let status = operation(base(service: service, account: account))
        guard shouldFallBackToLegacy(status) else { return status }
        return operation(base(service: service, account: account, dataProtection: false))
    }
}
#endif
