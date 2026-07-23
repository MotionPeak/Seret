import DebridCore
import Foundation

@MainActor
@Observable
public final class TraktAuthModel {
    public enum Phase: Equatable {
        case idle
        case requestingCode
        case awaiting(TraktDeviceCode)
        case linked
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// Bumped by `retry()`; drives the view's `.task(id:)` so a retry restarts the run.
    public private(set) var attempt = 0

    private let flow: TraktAuthFlow
    private let onLinked: () -> Void

    public init(flow: TraktAuthFlow, onLinked: @escaping () -> Void) {
        self.flow = flow
        self.onLinked = onLinked
    }

    public func run() async {
        phase = .requestingCode
        do {
            let code = try await flow.begin()
            phase = .awaiting(code)
            try await flow.awaitLink(code)
            phase = .linked
            onLinked()
        } catch is CancellationError {
            // leave state untouched
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    public func retry() { attempt += 1 }

    static func message(for error: Error) -> String {
        if let e = error as? TraktAuthError {
            switch e {
            case .deviceCodeExpired: return "The code expired. Tap to try again."
            case .deniedOrUsed: return "Linking was denied. Tap to try again."
            }
        }
        return "Couldn't reach Trakt. Check your connection and try again."
    }
}
