import Foundation

public enum HTTPError: Error, Equatable, Sendable {
    case transport(String)
    case status(code: Int, body: String)
    case decoding(String)
}
