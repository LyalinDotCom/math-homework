import UIKit
import ImageIO

/// Decodes bounded thumbnails so list rows never hold full 4K page scans.
enum Thumbnailer {
    static func thumbnail(from data: Data, maxPixel: CGFloat = 320) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func thumbnail(from url: URL, maxPixel: CGFloat = 320) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return thumbnail(from: data, maxPixel: maxPixel)
    }
}
