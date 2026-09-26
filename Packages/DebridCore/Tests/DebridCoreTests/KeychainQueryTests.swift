#if canImport(Security)
import Security
import Testing
@testable import DebridCore

/// The query shape is what differs by platform, so it is what is tested. The Keychain itself needs a
/// signed host app and is verified in the running Mac app (sign in, quit, relaunch: still signed in).
@Suite struct KeychainQueryTests {
    @Test func theQueryNamesTheItem() {
        let query = KeychainQuery.base(service: "svc", account: "acct")
        #expect(query[kSecAttrService as String] as? String == "svc")
        #expect(query[kSecAttrAccount as String] as? String == "acct")
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    }

    @Test func macOSAsksForTheDataProtectionKeychain() {
        let query = KeychainQuery.base(service: "svc", account: "acct")
        #if os(macOS)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #else
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
        #endif
    }

    @Test func theLegacyQueryDoesNotAsk() {
        let query = KeychainQuery.base(service: "svc", account: "acct", dataProtection: false)
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test func onlyAMissingEntitlementFallsBack() {
        #expect(KeychainQuery.shouldFallBackToLegacy(errSecMissingEntitlement) == KeychainQuery.prefersDataProtection)
        #expect(KeychainQuery.shouldFallBackToLegacy(errSecItemNotFound) == false)
        #expect(KeychainQuery.shouldFallBackToLegacy(errSecSuccess) == false)
    }

    @Test func performRetriesAgainstTheLegacyKeychainOnlyAfterAMissingEntitlement() {
        var asked: [Bool] = []
        let status = KeychainQuery.perform(service: "s", account: "a") { query in
            let dataProtection = (query[kSecUseDataProtectionKeychain as String] as? Bool) ?? false
            asked.append(dataProtection)
            return dataProtection ? errSecMissingEntitlement : errSecSuccess
        }
        #expect(status == errSecSuccess)
        #if os(macOS)
        #expect(asked == [true, false])
        #else
        #expect(asked == [false])
        #endif
    }

    @Test func performDoesNotRetryAnOrdinaryFailure() {
        var calls = 0
        let status = KeychainQuery.perform(service: "s", account: "a") { _ in calls += 1; return errSecItemNotFound }
        #expect(status == errSecItemNotFound)
        #expect(calls == 1)
    }
}
#endif
