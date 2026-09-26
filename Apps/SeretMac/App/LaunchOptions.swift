import Foundation

/// What the process was launched to do, read from its arguments and environment.
struct LaunchOptions: Equatable {
    /// The value after `-uiPreview`: a DEBUG harness case to boot straight into.
    var uiPreview: String?
    /// True when Xcode hosts the unit tests in this process — the app must not drive live UI.
    var isRunningTests: Bool

    init(arguments: [String], environment: [String: String]) {
        if let index = arguments.firstIndex(of: "-uiPreview"), index + 1 < arguments.count {
            uiPreview = arguments[index + 1]
        } else {
            uiPreview = nil
        }
        isRunningTests = environment["XCTestConfigurationFilePath"] != nil
    }

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments,
                                       environment: ProcessInfo.processInfo.environment)
}
