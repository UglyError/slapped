import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum StickerCutout {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Turns a photo into a clean, front-facing sticker: lifts the object nearest the centre,
    /// evens out the lighting, straightens it, and adds a white die-cut border with a little gloss.
    /// Returns nil when Vision can't find a subject (or on the Simulator, which lacks the model).
    static func cutout(_ image: UIImage) async -> UIImage? {
        let input = image.resized(maxDimension: 1600)
        return await Task.detached(priority: .userInitiated) { process(input) }.value
    }

    private static func process(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let maskBuffer = try? observation.generateScaledMaskForImage(
                  forInstances: centeredInstance(in: observation), from: handler)
        else { return nil }

        let source = CIImage(cgImage: cgImage)
        let mask = refined(CIImage(cvPixelBuffer: maskBuffer), extent: source.extent)
        var sticker = corrected(source, within: mask).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])

        guard let maskImage = context.createCGImage(mask, from: mask.extent, format: .L8,
                                                    colorSpace: CGColorSpaceCreateDeviceGray()) else { return nil }
        let shape = MaskShape(maskImage)
        guard shape.area > 0 else { return nil }

        if let quad = rectangle(in: maskImage, matchingArea: shape.area) {
            // rectangular sticker shot at an angle: flatten it to face-on
            let w = CGFloat(maskImage.width), h = CGFloat(maskImage.height)
            func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }
            sticker = sticker.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": point(quad.topLeft),
                "inputTopRight": point(quad.topRight),
                "inputBottomLeft": point(quad.bottomLeft),
                "inputBottomRight": point(quad.bottomRight),
            ])
        } else {
            sticker = sticker.cropped(to: shape.bounds)
            if abs(shape.angle) > 0.03 && shape.elongation > 1.15 {
                // level the long edge of non-round stickers
                sticker = sticker.transformed(by: CGAffineTransform(rotationAngle: shape.angle))
            }
        }

        guard let rendered = context.createCGImage(sticker, from: sticker.extent),
              let trimmed = rendered.trimmingTransparentEdges() else { return nil }
        return dieCut(trimmed)
    }

    /// The instance under the centre of the frame, falling back to every instance.
    private static func centeredInstance(in observation: VNInstanceMaskObservation) -> IndexSet {
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return observation.allInstances }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let labels = base.assumingMemoryBound(to: UInt8.self)
        // sample a small cross around the centre in case the very middle is a gap
        for (dx, dy) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
            let x = width / 2 + dx * width / 10, y = height / 2 + dy * height / 10
            let label = Int(labels[y * row + x])
            if label != 0, observation.allInstances.contains(label) { return IndexSet(integer: label) }
        }
        return observation.allInstances
    }

    /// Cleans Vision's soft, wobbly mask: fills pinholes, shaves off the background halo,
    /// and turns the edge into a crisp anti-aliased line.
    private static func refined(_ mask: CIImage, extent: CGRect) -> CIImage {
        let radius = max(2, extent.width / 400)
        return mask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius * 2])   // close holes…
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius * 2])   // …keeping the size
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])       // shave the halo
            .applyingGaussianBlur(sigma: Double(radius) * 0.8)
            .applyingFilter("CIColorMatrix", parameters: [                                         // re-sharpen the edge
                "inputRVector": CIVector(x: 6, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 6, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 6, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -2.5, y: -2.5, z: -2.5, w: 0),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: extent)
    }

    /// Gentle, sticker-only lighting fix: recover glare and shadows, then nudge exposure
    /// only if the sticker itself is clearly too dark or too bright.
    private static func corrected(_ image: CIImage, within mask: CIImage) -> CIImage {
        var output = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 0.85,
            "inputShadowAmount": 0.25,
        ])
        if let brightness = averageBrightness(of: output, within: mask) {
            let target = 0.55
            if brightness < 0.38 || brightness > 0.78 {
                let ev = max(-0.6, min(0.9, log2(target / max(brightness, 0.05))))
                output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
            }
        }
        return output
            .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.12])
            .cropped(to: image.extent)
    }

    private static func averageBrightness(of image: CIImage, within mask: CIImage) -> Double? {
        let masked = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        let average = masked.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: CGColorSpaceCreateDeviceRGB())
        let alpha = Double(pixel[3])
        guard alpha > 0.01 else { return nil }
        // premultiplied: divide by coverage to get the sticker's own average
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / alpha
    }

    /// A rectangle whose area matches the mask, i.e. the sticker itself is rectangular.
    private static func rectangle(in mask: CGImage, matchingArea area: CGFloat) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.15
        request.quadratureTolerance = 35
        request.minimumSize = 0.1
        try? VNImageRequestHandler(cgImage: mask, options: [:]).perform([request])
        guard let quad = request.results?.first else { return nil }
        let w = CGFloat(mask.width), h = CGFloat(mask.height)
        let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { CGPoint(x: $0.x * w, y: $0.y * h) }
        var doubled: CGFloat = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            doubled += a.x * b.y - b.x * a.y
        }
        let ratio = area / max(abs(doubled) / 2, 1)
        return (0.85...1.12).contains(ratio) ? quad : nil
    }

    /// White die-cut border plus a soft diagonal sheen, like a real vinyl sticker.
    private static func dieCut(_ image: CGImage) -> UIImage? {
        let border = max(8, CGFloat(max(image.width, image.height)) * 0.035)
        let canvas = CGRect(x: 0, y: 0,
                            width: CGFloat(image.width) + border * 4,
                            height: CGFloat(image.height) + border * 4)
        let art = CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: border * 2, y: border * 2))

        let silhouette = art.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        // grow, then blur + threshold so the border follows smooth curves like a real die-cut
        let backing = silhouette
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: border])
            .applyingGaussianBlur(sigma: Double(border) * 0.45)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 5),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -2),
            ])
            .applyingFilter("CIColorClamp")
            .applyingGaussianBlur(sigma: 0.8)
            .cropped(to: canvas)
        let clear = CIImage(color: .clear).cropped(to: canvas)
        let sticker = art.composited(over: backing).composited(over: clear)

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: canvas.height)
        gradient.point1 = CGPoint(x: canvas.width * 0.55, y: canvas.height * 0.45)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.08)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        let sheen = (gradient.outputImage ?? clear).cropped(to: canvas)
            .applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: sticker])

        guard let output = context.createCGImage(sheen, from: canvas) else { return nil }
        return UIImage(cgImage: output)
    }
}

/// Area, bounding box and orientation of a subject mask (image moments on a downsampled copy).
private struct MaskShape {
    var area: CGFloat = 0
    var bounds: CGRect = .zero       // Core Image coordinates (origin bottom-left)
    var angle: CGFloat = 0           // Core Image rotation that levels the long axis
    var elongation: CGFloat = 1

    init(_ mask: CGImage) {
        let fullW = CGFloat(mask.width), fullH = CGFloat(mask.height)
        let scale = min(1, 256 / max(fullW, fullH))
        let w = max(1, Int(fullW * scale)), h = max(1, Int(fullH * scale))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return }

        // row 0 of the buffer is the top of the image (y grows downwards)
        var m00 = 0.0, m10 = 0.0, m01 = 0.0
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[y * w + x] > 127 {
                m00 += 1; m10 += Double(x); m01 += Double(y)
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard m00 > 0 else { return }
        let cx = m10 / m00, cy = m01 / m00
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0
        for y in minY...maxY {
            for x in minX...maxX where pixels[y * w + x] > 127 {
                let dx = Double(x) - cx, dy = Double(y) - cy
                mu20 += dx * dx; mu02 += dy * dy; mu11 += dx * dy
            }
        }

        // principal axis, measured clockwise on screen; rotating CI (y-up) by the same angle levels it
        var theta = 0.5 * atan2(2 * mu11, mu20 - mu02)
        if theta > .pi / 4 { theta -= .pi / 2 } else if theta < -.pi / 4 { theta += .pi / 2 }
        angle = CGFloat(theta)
        let spread = sqrt(4 * mu11 * mu11 + (mu20 - mu02) * (mu20 - mu02))
        let major = (mu20 + mu02 + spread) / 2, minor = (mu20 + mu02 - spread) / 2
        elongation = CGFloat(sqrt(major / max(minor, 1e-6)))

        let inverse = 1 / scale
        area = CGFloat(m00) * inverse * inverse
        let boxW = CGFloat(maxX - minX + 1) * inverse, boxH = CGFloat(maxY - minY + 1) * inverse
        bounds = CGRect(x: CGFloat(minX) * inverse, y: fullH - CGFloat(minY) * inverse - boxH, width: boxW, height: boxH)
            .insetBy(dx: -2 * inverse, dy: -2 * inverse)
            .intersection(CGRect(x: 0, y: 0, width: fullW, height: fullH))
    }
}

enum DuplicateDetector {
    /// Feature-print distance below which two stickers count as the same one.
    static let sameThreshold: Float = 0.45
    /// Between the two thresholds we show both and ask the user.
    static let askThreshold: Float = 0.75

    struct Match {
        let sticker: StickerCard
        let distance: Float
    }

    /// Compares what's in the new sticker (not its raw pixels) against stickers logged nearby,
    /// so a different angle, distance or light still matches.
    static func closestMatch(for image: UIImage, among candidates: [StickerCard]) async -> Match? {
        guard !candidates.isEmpty else { return nil }
        return await Task.detached(priority: .userInitiated) { () async -> Match? in
            let prints = (0..<4).compactMap { featurePrint(image.rotated(quarterTurns: $0)) }
            guard !prints.isEmpty else { return nil }
            var best: Match?
            for candidate in candidates {
                guard let url = candidate.imageURL,
                      let data = try? await URLSession.shared.data(from: url).0,
                      let other = UIImage(data: data),
                      let otherPrint = featurePrint(other) else { continue }
                for candidatePrint in prints {
                    var distance = Float.greatestFiniteMagnitude
                    guard (try? candidatePrint.computeDistance(&distance, to: otherPrint)) != nil else { continue }
                    if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                        best = Match(sticker: candidate, distance: distance)
                    }
                }
            }
            return best
        }.value
    }

    private static func featurePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.flattened(maxDimension: 512).cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.imageCropAndScaleOption = .scaleFit
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return request.results?.first
    }
}

enum PerceptualHash {
    /// dHash of the image at 0°, 90°, 180° and 270°. The server uses it as a last-line check
    /// against near-identical uploads; the feature-print check above handles real-world angles.
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

extension CGImage {
    /// Crops away fully transparent margins.
    func trimmingTransparentEdges() -> CGImage? {
        let w = width, h = height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
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

    /// Downscaled copy on a white background (no transparency).
    func flattened(maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.singleScale
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
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
