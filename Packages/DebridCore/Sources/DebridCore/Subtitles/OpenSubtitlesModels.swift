import Foundation

// Decode-only wire models for OpenSubtitles api/v1. snake_case → CodingKeys (the package
// decoder does no key conversion, matching TMDBModels).

struct OSSearchResponse: Decodable {
    let data: [OSSubtitle]
}

struct OSSubtitle: Decodable {
    let attributes: OSAttributes
}

struct OSAttributes: Decodable {
    let language: String?
    let release: String?
    let downloadCount: Int?
    let fps: Double?
    let hearingImpaired: Bool?
    let fromTrusted: Bool?
    let aiTranslated: Bool?
    let moviehashMatch: Bool?
    let uploader: OSUploader?
    let files: [OSFile]

    enum CodingKeys: String, CodingKey {
        case language, release, fps, uploader, files
        case downloadCount = "download_count"
        case hearingImpaired = "hearing_impaired"
        case fromTrusted = "from_trusted"
        case aiTranslated = "ai_translated"
        case moviehashMatch = "moviehash_match"
    }
}

struct OSUploader: Decodable {
    let name: String?
}

struct OSFile: Decodable {
    let fileID: Int
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
    }
}

struct OSLoginResponse: Decodable {
    let token: String
}

struct OSDownloadResponse: Decodable {
    let link: String
    let fileName: String?
    let remaining: Int?
    let resetTimeUTC: String?

    enum CodingKeys: String, CodingKey {
        case link, remaining
        case fileName = "file_name"
        case resetTimeUTC = "reset_time_utc"
    }
}
