import CoreGraphics

/// Per-side pixel insets for the edge controls. Positive values move that edge inward.
/// Ported from BorderTrim.
struct ManualInsets: Equatable {
    var top = 0
    var left = 0
    var bottom = 0
    var right = 0

    static let zero = ManualInsets()

    init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// Insets that describe an existing crop rect inside an image of `imageSize`.
    init(rect: CGRect, imageSize: CGSize) {
        self.init(
            top: Int(rect.minY),
            left: Int(rect.minX),
            bottom: Int(imageSize.height - rect.maxY),
            right: Int(imageSize.width - rect.maxX)
        )
    }

    /// The crop rect in top-left-origin pixel coordinates, clamped so each side keeps 1px.
    func cropRect(in imageSize: CGSize) -> CGRect {
        let x = CGFloat(max(0, left))
        let y = CGFloat(max(0, top))
        let width = max(1, imageSize.width - x - CGFloat(max(0, right)))
        let height = max(1, imageSize.height - y - CGFloat(max(0, bottom)))
        return CGRect(x: min(x, imageSize.width - 1), y: min(y, imageSize.height - 1), width: width, height: height)
    }
}
