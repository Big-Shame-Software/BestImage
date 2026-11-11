import SwiftUI

/// BestImage's hero object: a pixel floppy disk with a photo and the rainbow
/// stripe on its label. Same 22-cell grid as the app icon (.github/brand/icon-master.svg).
/// Brand surfaces only (About window, empty state).
struct PixelDisk: View {
    var size: CGFloat = 88

    private typealias Cell = (x: Int, y: Int, w: Int, h: Int, color: Color)

    private static let cells: [Cell] = {
        let plum = BSSBrand.plumInk, cream = BSSBrand.cream
        var c: [Cell] = [
            // shutter
            (5, 1, 12, 7, plum), (6, 1, 10, 6, BSSBrand.dust), (12, 2, 3, 4, plum),
            // label
            (3, 10, 16, 11, plum), (4, 11, 14, 10, cream),
            // photo on the label: sun and mountains
            (13, 12, 2, 2, BSSBrand.sunsetOrange),
            (7, 14, 1, 1, plum), (6, 15, 3, 1, plum), (5, 16, 5, 1, plum),
            (10, 15, 1, 1, plum), (9, 16, 3, 1, plum),
            // highlight, top-left
            (2, 2, 2, 1, cream), (2, 3, 1, 2, cream),
        ]
        for (i, color) in BSSBrand.rainbow.enumerated() { c.append((4, 17 + i, 14, 1, color)) }
        return c
    }()

    var body: some View {
        Canvas { ctx, canvasSize in
            let u = canvasSize.width / 22
            // Body with clipped top-right corner: plum outline, beige fill.
            func body(inset: CGFloat, corner: CGFloat) -> Path {
                Path { p in
                    p.move(to: CGPoint(x: inset * u, y: inset * u))
                    p.addLine(to: CGPoint(x: (19 - corner) * u + inset * u * 0.5, y: inset * u))
                    p.addLine(to: CGPoint(x: (22 - inset) * u, y: (3 + inset * 0.5) * u))
                    p.addLine(to: CGPoint(x: (22 - inset) * u, y: (22 - inset) * u))
                    p.addLine(to: CGPoint(x: inset * u, y: (22 - inset) * u))
                    p.closeSubpath()
                }
            }
            ctx.fill(body(inset: 0, corner: 0), with: .color(BSSBrand.plumInk))
            ctx.fill(body(inset: 1, corner: 0.5), with: .color(BSSBrand.computerBeige))
            for cell in Self.cells {
                let r = CGRect(x: CGFloat(cell.x) * u, y: CGFloat(cell.y) * u,
                               width: CGFloat(cell.w) * u, height: CGFloat(cell.h) * u)
                ctx.fill(Path(r), with: .color(cell.color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Three-ray starburst accent in magenta, yellow and cyan (styleguide §2, §6).
struct Starburst: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { ctx, s in
            let rays: [(angle: Double, color: Color)] = [
                (-80, BSSBrand.hotMagenta), (-45, BSSBrand.sunshineYellow), (-10, BSSBrand.aquaCyan),
            ]
            let origin = CGPoint(x: s.width * 0.05, y: s.height * 0.95)
            for ray in rays {
                let a = ray.angle * .pi / 180
                let inner = s.width * 0.35, outer = s.width * 0.95
                var p = Path()
                p.move(to: CGPoint(x: origin.x + cos(a) * inner, y: origin.y + sin(a) * inner))
                p.addLine(to: CGPoint(x: origin.x + cos(a) * outer, y: origin.y + sin(a) * outer))
                ctx.stroke(p, with: .color(ray.color), style: StrokeStyle(lineWidth: s.width * 0.16, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
