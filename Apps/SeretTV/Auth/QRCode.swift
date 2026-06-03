import CoreImage.CIFilterBuiltins
import SwiftUI

/// Generates a crisp QR `Image` from a string (e.g. the RD verification URL).
enum QRCode {
    private static let context = CIContext()

    static func image(from string: String, scale: CGFloat = 12) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return Image(decorative: cg, scale: 1, orientation: .up)
    }
}
