import CoreGraphics
import Foundation

/// Finds the subject of an image that sits on a transparent or near-white background and
/// cuts the background away.
///
/// Background and shadow pixels are only removed when they are connected to the image edge
/// through other background-like pixels. That keeps white areas enclosed by the subject
/// (eyes, highlights, a white dress) and stops soft gray drop shadows from being treated as
/// part of the subject, which is what usually makes cutouts look dirty.
enum CutoutDetector {
    enum Background: Sendable {
        case transparent
        case white
        case none
    }

    struct Analysis: Sendable {
        let width: Int
        let height: Int
        /// Tight pixel bounds of the subject, origin at the top-left like `CGImage`.
        let subjectBounds: CGRect
        let background: Background
        /// Premultiplied RGBA of the original image.
        let source: [UInt8]
        /// True where the automatic pass decided the pixel is background or shadow.
        let removed: [Bool]

        /// Renders the image with background made transparent. `overrides` holds one byte per
        /// pixel: 0 = automatic, 1 = keep (restored with the brush), 2 = remove (erased).
        func cutout(overrides: [UInt8]) -> CGImage? {
            var bytes = source
            for index in 0..<(width * height) {
                let override = overrides.isEmpty ? 0 : overrides[index]
                let isRemoved = override == 2 || (override == 0 && removed[index])
                guard isRemoved else { continue }
                let o = index * 4
                bytes[o] = 0
                bytes[o + 1] = 0
                bytes[o + 2] = 0
                bytes[o + 3] = 0
            }
            return CutoutDetector.makeImage(from: bytes, width: width, height: height)
        }
    }

    /// Luminance (0–255) at or above which a neutral pixel is treated as shadow when it is
    /// connected to the background.
    static let defaultShadowLevel = 214
    static let shadowLevelRange = 150...246

    /// Pixels at or above this level seed the removal from the image edge.
    private static let seedLevel = 238
    /// Max channel spread for a pixel to count as neutral (white, gray or black, not colored).
    private static let maxNeutralChroma = 24

    static func analyze(_ image: CGImage, shadowLevel: Int = defaultShadowLevel) -> Analysis? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let count = width * height

        // Premultiplied RGBA as it is stored in the image, so transparency is kept.
        var rgba = [UInt8](repeating: 0, count: count * 4)
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
        guard drawn else { return nil }

        // Classify every pixel as it looks when composited over white, so transparent pixels
        // count as background.
        var canFlood = [Bool](repeating: false, count: count)   // neutral and at least shadow-bright
        var isSeed = [Bool](repeating: false, count: count)     // neutral and bright enough to start removal
        for i in 0..<count {
            let o = i * 4
            let alpha = Int(rgba[o + 3])
            let whiteShowing = 255 - alpha
            let r = Int(rgba[o]) + whiteShowing
            let g = Int(rgba[o + 1]) + whiteShowing
            let b = Int(rgba[o + 2]) + whiteShowing
            let luminance = (r * 77 + g * 150 + b * 29) >> 8
            let chroma = max(r, g, b) - min(r, g, b)
            guard chroma <= maxNeutralChroma else { continue }
            canFlood[i] = luminance >= shadowLevel
            isSeed[i] = luminance >= seedLevel
        }

        // Flood the background in from every edge pixel that is bright enough to be background.
        var removed = [Bool](repeating: false, count: count)
        var queue = [Int32]()
        queue.reserveCapacity(count / 16)

        func enqueueIfRemovable(_ index: Int) {
            guard !removed[index], canFlood[index] else { return }
            removed[index] = true
            queue.append(Int32(index))
        }

        var removedBorderPixels = 0
        var transparentBorderPixels = 0
        for x in 0..<width {
            for index in [x, (height - 1) * width + x] where isSeed[index] {
                enqueueIfRemovable(index)
            }
        }
        for y in 0..<height {
            for index in [y * width, y * width + width - 1] where isSeed[index] {
                enqueueIfRemovable(index)
            }
        }

        var head = 0
        while head < queue.count {
            let index = Int(queue[head])
            head += 1
            let x = index % width
            if x > 0 { enqueueIfRemovable(index - 1) }
            if x < width - 1 { enqueueIfRemovable(index + 1) }
            if index >= width { enqueueIfRemovable(index - width) }
            if index + width < count { enqueueIfRemovable(index + width) }
        }

        // Describe the background from the outer edge.
        for index in borderIndices(width: width, height: height) {
            if rgba[index * 4 + 3] < 128 { transparentBorderPixels += 1 }
            if removed[index] { removedBorderPixels += 1 }
        }
        let background: Background
        if transparentBorderPixels > 0 {
            background = .transparent
        } else if removedBorderPixels > 0 {
            background = .white
        } else {
            background = .none
        }

        // Tight bounds of what is left. Rows and columns with only a few stray pixels are
        // ignored so specks and compression noise do not stretch the box.
        var rowCounts = [Int](repeating: 0, count: height)
        var columnCounts = [Int](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if !removed[index], rgba[index * 4 + 3] > 0 {
                    rowCounts[y] += 1
                    columnCounts[x] += 1
                }
            }
        }
        let minRowCount = max(3, width / 250)
        let minColumnCount = max(3, height / 250)
        let rows = rowCounts.indices.filter { rowCounts[$0] >= minRowCount }
        let columns = columnCounts.indices.filter { columnCounts[$0] >= minColumnCount }
        let subjectBounds: CGRect
        if let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last {
            subjectBounds = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        } else {
            subjectBounds = CGRect(x: 0, y: 0, width: width, height: height)
        }

        return Analysis(
            width: width,
            height: height,
            subjectBounds: subjectBounds,
            background: background,
            source: rgba,
            removed: removed
        )
    }

    private static func borderIndices(width: Int, height: Int) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity(2 * (width + height))
        for x in 0..<width {
            indices.append(x)
            indices.append((height - 1) * width + x)
        }
        for y in 0..<height {
            indices.append(y * width)
            indices.append(y * width + width - 1)
        }
        return indices
    }

    static func makeImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
