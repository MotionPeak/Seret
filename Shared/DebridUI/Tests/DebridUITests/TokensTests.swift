import Testing
import SwiftUI
@testable import DebridUI

@Test func tokensAreSane() {
    // Posters are 2:3 ≈ 0.667. Exact `==` on a computed CGFloat is ULP-fragile, so compare
    // with a tolerance.
    #expect((Tokens.posterAspect - 2.0 / 3.0).magnitude < 1e-9)
    #expect(Tokens.gridSpacing > 0)
    #expect(Tokens.cornerRadius >= 0)
}
