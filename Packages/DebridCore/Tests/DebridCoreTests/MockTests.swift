import Testing

/// Top-level serialized container for every test suite that touches
/// MockURLProtocol's shared global state.  Nesting suites here causes
/// Swift Testing to schedule all their tests serially so stubs cannot bleed.
@Suite(.serialized)
struct MockTests {}
