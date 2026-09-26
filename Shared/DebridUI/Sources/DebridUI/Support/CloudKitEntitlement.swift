import Foundation
#if os(macOS)
import Security
#endif

/// Whether this process may use CloudKit at all.
///
/// iOS and tvOS builds always carry the iCloud entitlement. A Mac development build may not — it can
/// be signed locally without a provisioning profile — and asking SwiftData for a CloudKit container
/// without the entitlement fails at run time. So on macOS the answer is read from the running binary
/// itself; everywhere else it is yes.
public enum CloudKitEntitlement {
    public static var isPresent: Bool {
        #if os(macOS)
        return hasCloudKitService(in: currentProcessEntitlement("com.apple.developer.icloud-services"))
        #else
        return true
        #endif
    }

    /// Whether an `icloud-services` entitlement value names CloudKit.
    static func hasCloudKitService(in value: Any?) -> Bool {
        (value as? [String])?.contains("CloudKit") ?? false
    }

    #if os(macOS)
    private static func currentProcessEntitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
    #endif
}
