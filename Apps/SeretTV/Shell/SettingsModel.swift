import Observation
import DebridCore

@MainActor
@Observable
final class SettingsModel {
    var username: String = ""
    var password: String = ""
    private(set) var isConnected: Bool

    private let secretStore: SecretStore

    init(secretStore: SecretStore) {
        self.secretStore = secretStore
        if let account = secretStore.readAccount() {
            username = account.username
            isConnected = true
        } else {
            isConnected = false
        }
    }

    func save() {
        let u = username.trimmingCharacters(in: .whitespaces)
        let p = password   // passwords are NOT trimmed — leading/trailing spaces can be significant
        guard !u.isEmpty, !p.isEmpty else { return }
        try? secretStore.writeAccount(.init(username: u, password: p))
        isConnected = secretStore.readAccount() != nil
    }

    func remove() {
        try? secretStore.clear()
        username = ""
        password = ""
        isConnected = false
    }
}
