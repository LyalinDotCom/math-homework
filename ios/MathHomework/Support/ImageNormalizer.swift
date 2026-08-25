import UIKit

/// Port of the desktop app's image normalization: every capture or import is
/// re-encoded as an upright, bounded JPEG before it is stored or uploaded.
enum ImageNormalizer {
    enum NormalizeError: LocalizedError {
        case tooSmall
        case couldNotEncode

        var errorDescription: String? {
            switch self {
            case .tooSmall: return "Selected image dimensions are invalid"
            case .couldNotEncode: return "Selected image could not be normalized safely"
            }
        }
    }

    static let maxDimension: CGFloat = 4_096
    static let jpegQuality: CGFloat = 0.92

    static func normalizedJPEG(from image: UIImage) throws -> Data {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth >= 200, pixelHeight >= 200 else { throw NormalizeError.tooSmall }

        let scale = min(1, maxDimension / pixelWidth, maxDimension / pixelHeight)
        let targetSize = CGSize(
            width: (pixelWidth * scale).rounded(),
            height: (pixelHeight * scale).rounded()
        )

        // Redrawing also bakes in EXIF orientation, so the archived JPEG is
        // upright everywhere it is read.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = rendered.jpegData(compressionQuality: jpegQuality),
              jpeg.count >= 1_000, jpeg.count <= 18 * 1024 * 1024
        else { throw NormalizeError.couldNotEncode }
        return jpeg
    }
}
