import Testing
@testable import DebridUI

@Suite struct CloudKitEntitlementTests {
    @Test func anICloudServicesListNamingCloudKitCounts() {
        #expect(CloudKitEntitlement.hasCloudKitService(in: ["CloudKit"]))
        #expect(CloudKitEntitlement.hasCloudKitService(in: ["CloudDocuments", "CloudKit"]))
    }

    @Test func anythingElseDoesNot() {
        #expect(!CloudKitEntitlement.hasCloudKitService(in: ["CloudDocuments"]))
        #expect(!CloudKitEntitlement.hasCloudKitService(in: nil))
        #expect(!CloudKitEntitlement.hasCloudKitService(in: "CloudKit"))      // wrong type
    }

    #if os(macOS)
    /// The `swift test` runner carries no iCloud entitlement — exactly the locally signed case.
    @Test func thisUnsignedTestProcessIsNotEntitled() {
        #expect(!CloudKitEntitlement.isPresent)
    }
    #endif
}
