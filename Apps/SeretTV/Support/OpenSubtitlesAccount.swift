import Foundation
import DebridCore

struct OpenSubtitlesAccount: Codable, Equatable {
    var username: String
    var password: String
}

extension SecretStore {
    func readAccount() -> OpenSubtitlesAccount? {
        guard let data = try? read() else { return nil }
        return try? JSONDecoder().decode(OpenSubtitlesAccount.self, from: data)
    }
    func writeAccount(_ account: OpenSubtitlesAccount) throws {
        try write(JSONEncoder().encode(account))
    }
}

extension OpenSubtitlesAccount {
    var credentials: OpenSubtitlesProvider.Credentials {
        .init(username: username, password: password)
    }
}
