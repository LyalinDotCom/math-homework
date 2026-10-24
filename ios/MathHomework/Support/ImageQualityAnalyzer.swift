import Foundation
import CoreGraphics
import ImageIO
import Vision

enum ImageQualityAnalyzer {
    struct Assessment: Equatable {
        let blurScore: Double
        let recognizedRegions: Int
        let warning: String?
    }

    /// A conservative preflight, not a guarantee that faint pencil is legible.
    /// Vision checks printed text independently of Gemini. The sharpness score
    /// is measured at a fixed resolution so camera pixel counts don't bias it.
    static func assess(_ data: Data) throws -> Assessment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ContractError.invalid("The saved scan could not be opened. Retake this page.")
        }
        let ratio = min(1, 1_200 / Double(max(image.width, image.height)))
        let width = max(3, Int(Double(image.width) * ratio))
        let height = max(3, Int(Double(image.height) * ratio))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw ContractError.invalid("The scan could not be checked. Retake the page or choose Read Anyway.") }
        var sum = 0.0, square = 0.0, count = 0.0
        // Exclude the outside border: the edge of a blurry sheet can be sharp.
        for y in max(1, height / 20)..<(height - max(1, height / 20)) {
            for x in max(1, width / 20)..<(width - max(1, width / 20)) {
                let i = y * width + x
                let value = Double(4 * Int(pixels[i]) - Int(pixels[i - 1]) - Int(pixels[i + 1])
                    - Int(pixels[i - width]) - Int(pixels[i + width]))
                sum += value
                square += value * value
                count += 1
            }
        }
        let score = count > 0 ? square / count - pow(sum / count, 2) : 0
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        let confident = observations.filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.5 }.count
        let warning: String?
        if min(image.width, image.height) < 600 {
            warning = "This page has too little detail to read reliably. Move closer and retake it."
        } else if score < 18 || confident < 3 {
            warning = "This scan may be blurry, faint, blank, or cropped. Retake it in good light, or inspect it and choose Read Anyway."
        } else {
            warning = nil
        }
        OCRDiagnostics.record("image_quality", fields: ["blur_score": String(format: "%.1f", score),
            "text_regions": String(confident), "warning": String(warning != nil)])
        return Assessment(blurScore: score, recognizedRegions: confident, warning: warning)
    }
}
