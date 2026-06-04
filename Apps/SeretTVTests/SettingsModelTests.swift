import Testing
import Foundation
import DebridCore
@testable import Seret

@MainActor
@Suite struct SettingsModelTests {
    @Test func savesAndReportsConnected() throws {
        let store = InMemorySecretStore()
        let model = SettingsModel(secretStore: store)
        #expect(model.isConnected == false)

        model.username = "neo"
        model.password = "trinity"
        model.save()

        #expect(model.isConnected == true)
        #expect(store.readAccount() == OpenSubtitlesAccount(username: "neo", password: "trinity"))
    }

    @Test func removeClearsCredentials() throws {
        let store = InMemorySecretStore()
        try store.writeAccount(.init(username: "neo", password: "trinity"))
        let model = SettingsModel(secretStore: store)
        #expect(model.isConnected == true)

        model.remove()
        #expect(model.isConnected == false)
        #expect(store.readAccount() == nil)
        #expect(model.username == "")
    }

    @Test func blankUsernameOrPasswordDoesNotSave() {
        let store = InMemorySecretStore()
        let model = SettingsModel(secretStore: store)
        model.username = "  "
        model.password = ""
        model.save()
        #expect(model.isConnected == false)
        #expect(store.readAccount() == nil)
    }
}
