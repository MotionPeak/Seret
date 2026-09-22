import Testing
@testable import Seret

@Suite struct LaunchOptionsTests {
    @Test func readsThePreviewCaseAfterTheFlag() {
        let options = LaunchOptions(arguments: ["Seret", "-uiPreview", "shell"], environment: [:])
        #expect(options.uiPreview == "shell")
        #expect(options.isRunningTests == false)
    }

    @Test func aFlagWithNoValueIsIgnored() {
        #expect(LaunchOptions(arguments: ["Seret", "-uiPreview"], environment: [:]).uiPreview == nil)
    }

    @Test func noFlagMeansNoPreview() {
        #expect(LaunchOptions(arguments: ["Seret"], environment: [:]).uiPreview == nil)
    }

    @Test func theXcodeTestHostIsDetected() {
        let options = LaunchOptions(arguments: ["Seret"], environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        #expect(options.isRunningTests)
    }
}
