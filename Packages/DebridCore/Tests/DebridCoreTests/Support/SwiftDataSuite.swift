import Testing

/// Serialized parent for EVERY SwiftData-backed suite. SwiftData creates a CoreData stack per
/// in-memory `ModelContainer`; running multiple SwiftData suites concurrently — even when each is
/// internally `.serialized` — intermittently SIGSEGVs the test runner (concurrent ModelContainer
/// lifecycle). Nesting every SwiftData suite under this parent serializes them relative to each
/// other, so only one `ModelContainer` is alive at a time. Same hazard + fix as `MockTests` for
/// the shared `MockURLProtocol` handler. Measured ~17% crash rate without this; 0 with it.
@Suite(.serialized) struct SwiftDataSuite {}
