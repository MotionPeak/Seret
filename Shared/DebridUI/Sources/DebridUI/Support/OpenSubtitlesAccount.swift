import Foundation
import DebridCore

public struct OpenSubtitlesAccount: Codable, Equatable {
    public var username: String
    public var password: String
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

extension SecretStore {
    public func readAccount() -> OpenSubtitlesAccount? {
        guard let data = try? read() else { return nil }
        return try? JSONDecoder().decode(OpenSubtitlesAccount.self, from: data)
    }
    public func writeAccount(_ account: OpenSubtitlesAccount) throws {
        try write(JSONEncoder().encode(account))
    }
}

extension OpenSubtitlesAccount {
    public var credentials: OpenSubtitlesProvider.Credentials {
        .init(username: username, password: password)
    }
}
