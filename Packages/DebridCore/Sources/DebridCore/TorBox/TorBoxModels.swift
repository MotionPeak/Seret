import Foundation

/// TorBox wraps every response in `{success, error, detail, data}`. Decode with
/// `.convertFromSnakeCase`.
struct TorBoxEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let error: String?
    let detail: String?
    let data: T?
}

/// One torrent from `GET /torrents/mylist` (snake_case keys, decoded with `.convertFromSnakeCase`).
public struct TorBoxTorrent: Decodable, Sendable, Equatable {
    public let id: Int
    public let hash: String
    public let name: String
    public let size: Int
    public let createdAt: String?
    public let downloadState: String?
    public let downloadFinished: Bool?
    public let downloadPresent: Bool?
    /// A 0…1 fraction (Real-Debrid reports 0…100).
    public let progress: Double?
    public let downloadSpeed: Int?
    public let seeds: Int?
    public let files: [TorBoxFile]?
}

public struct TorBoxFile: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let shortName: String?
    public let size: Int
    public let mimetype: String?
    public let zipped: Bool?
}

/// `GET /user/me`.
public struct TorBoxUser: Decodable, Sendable, Equatable {
    public let email: String?
    public let plan: Int
    public let premiumExpiresAt: String?

    public var planName: String {
        switch plan {
        case 0: return "Free"
        case 1: return "Essential"
        case 2: return "Pro"
        case 3: return "Standard"
        default: return "Plan \(plan)"
        }
    }

    /// The Free plan (0) can't use the API at all — `mylist` answers `PLAN_RESTRICTED_FEATURE`.
    public var isPaid: Bool { plan != 0 }
}
