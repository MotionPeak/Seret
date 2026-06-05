import Observation
import DebridCore

@MainActor
@Observable
public final class SettingsModel {
    public var username: String = ""
    public var password: String = ""
    public private(set) var isConnected: Bool

    private let secretStore: SecretStore

    public init(secretStore: SecretStore) {
        self.secretStore = secretStore
        if let account = secretStore.readAccount() {
            username = account.username
            isConnected = true
        } else {
            isConnected = false
        }
    }

    public func save() {
        let u = username.trimmingCharacters(in: .whitespaces)
        let p = password   // passwords are NOT trimmed — leading/trailing spaces can be significant
        guard !u.isEmpty, !p.isEmpty else { return }
        try? secretStore.writeAccount(.init(username: u, password: p))
        isConnected = secretStore.readAccount() != nil
    }

    public func remove() {
        try? secretStore.clear()
        username = ""
        password = ""
        isConnected = false
    }
}
