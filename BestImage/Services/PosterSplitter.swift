import CoreGraphics
import Foundation

/// Proposes one rectangle per item on a sheet (for example five posters in one image) by
/// finding the gutters between them. Rows are split first, then columns inside each row.
/// The result is a starting point: the crop sheet lets you adjust every box.
enum PosterSplitter {
    /// Pixels whose composited luminance is below this count as "ink" (poster art,
    /// black poster backgrounds, text). Light gray shadows and white gutters do not.
    static let defaultInkLevel = 200

    static func propose(_ image: CGImage, inkLevel: Int = defaultInkLevel) -> [CGRect] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }

        var ink = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) {
            let o = i * 4
            let whiteShowing = 255 - Int(rgba[o + 3])
            let r = Int(rgba[o]) + whiteShowing
            let g = Int(rgba[o + 1]) + whiteShowing
            let b = Int(rgba[o + 2]) + whiteShowing
            ink[i] = (r * 77 + g * 150 + b * 29) >> 8 < inkLevel
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        var boxes: [CGRect] = []
        for rowBand in bands(count: height, minLength: max(4, height / 60), isActive: { y in
            // Rows with a few stray ink pixels (noise) are still gutters.
            var count = 0
            for x in 0..<width where ink[y * width + x] { count += 1 }
            return count >= max(3, width / 200)
        }) {
            let bandHeight = rowBand.upperBound - rowBand.lowerBound
            for columnBand in bands(count: width, minLength: max(4, width / 60), isActive: { x in
                var count = 0
                for y in rowBand where ink[y * width + x] { count += 1 }
                return count >= max(3, bandHeight / 200)
            }) {
                boxes.append(CGRect(
                    x: columnBand.lowerBound,
                    y: rowBand.lowerBound,
                    width: columnBand.upperBound - columnBand.lowerBound,
                    height: bandHeight
                ))
            }
        }
        return boxes.isEmpty ? [fullRect] : boxes
    }

    /// Runs of consecutive "active" indices, dropping runs shorter than `minLength`.
    private static func bands(count: Int, minLength: Int, isActive: (Int) -> Bool) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for index in 0..<count {
            if isActive(index) {
                if start == nil { start = index }
            } else if let s = start {
                if index - s >= minLength { result.append(s..<index) }
                start = nil
            }
        }
        if let s = start, count - s >= minLength { result.append(s..<count) }
        return result
    }
}
