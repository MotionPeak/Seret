import Testing

/// Serialized parent for EVERY SwiftData-backed suite in this package, mirroring DebridCore's.
/// Two concurrent in-memory `ModelContainer`s intermittently SIGSEGV the test runner; nesting all
/// SwiftData suites here keeps only one alive at a time. Per-suite `.serialized` is NOT enough —
/// it only orders tests *within* a suite.
@Suite(.serialized) struct SwiftDataSuite {}
