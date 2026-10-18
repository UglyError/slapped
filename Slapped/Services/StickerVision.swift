import UIKit
import Vision
import CoreImage

enum StickerCutout {
    /// Lifts the main subject (the sticker) off its background, cropped tight with a transparent backdrop.
    /// Returns nil when Vision can't find a subject (or on the Simulator, which lacks the model).
    static func cutout(_ image: UIImage) async -> UIImage? {
        let input = image.resized(maxDimension: 1600)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cgImage = input.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
                let buffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances,
                    from: handler,
                    croppedToInstancesExtent: true
                )
                let ciImage = CIImage(cvPixelBuffer: buffer)
                guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
                return UIImage(cgImage: output)
            } catch {
                return nil
            }
        }.value
    }
}

enum PerceptualHash {
    /// dHash of the image at 0°, 90°, 180° and 270°, so the same sticker
    /// photographed at a different angle still matches on the server.
    static func rotationHashes(_ image: UIImage) -> [Int64] {
        let small = image.resized(maxDimension: 64)
        return (0..<4).map { dHash(small.rotated(quarterTurns: $0)) }
    }

    /// 64-bit difference hash: shrink to 9×8 grayscale and compare neighbouring pixels.
    static func dHash(_ image: UIImage) -> Int64 {
        guard let cgImage = image.cgImage else { return 0 }
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            // transparent cutout areas become white so the background never affects the hash
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(rect)
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: rect)
            return true
        }
        guard drew else { return 0 }

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                hash <<= 1
                if pixels[y * width + x] > pixels[y * width + x + 1] { hash |= 1 }
            }
        }
        return Int64(bitPattern: hash)
    }
}

extension UIImage {
    /// Downscales (never upscales) and bakes in orientation.
    func resized(maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: target, format: .singleScale).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    func rotated(quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return self }
        let target = turns.isMultiple(of: 2) ? size : CGSize(width: size.height, height: size.width)
        return UIGraphicsImageRenderer(size: target, format: .singleScale).image { ctx in
            ctx.cgContext.translateBy(x: target.width / 2, y: target.height / 2)
            ctx.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

private extension UIGraphicsImageRendererFormat {
    static var singleScale: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return format
    }
}
