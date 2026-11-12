import SwiftUI

/// The illustration behind the main screens: a pale sun over misty mountains, the ruin of a
/// classical colonnade on the left and a red maple growing from a rock on the right. Drawn with
/// a few paths in the theme colours, so it costs no image memory and follows light and dark.
struct Scenery: View {
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let dark = scheme == .dark
            let ink = Palette.text

            ctx.fill(circle(CGPoint(x: w * 0.40, y: h * 0.36), h * 0.25), with: .color(Palette.sun))

            ctx.fill(ridge(size, [0, 0.58, 0.14, 0.44, 0.28, 0.56, 0.44, 0.26, 0.58, 0.50, 0.72, 0.36, 0.88, 0.54, 1, 0.42]), with: .color(ink.opacity(dark ? 0.05 : 0.07)))
            ctx.fill(ridge(size, [0, 0.74, 0.16, 0.60, 0.30, 0.70, 0.46, 0.52, 0.62, 0.68, 0.80, 0.56, 1, 0.70]), with: .color(ink.opacity(dark ? 0.06 : 0.09)))
            ctx.fill(ridge(size, [0, 0.86, 0.22, 0.76, 0.44, 0.84, 0.66, 0.74, 0.84, 0.84, 1, 0.80]), with: .color(ink.opacity(dark ? 0.07 : 0.10)))

            colonnade(ctx, size, ink.opacity(dark ? 0.10 : 0.13))
            maple(ctx, size)

            // Fade into the page.
            let fade = Gradient(stops: [.init(color: Palette.bg.opacity(0), location: 0.5), .init(color: Palette.bg, location: 1)])
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// A soft mountain silhouette through points given as x, y fractions of the canvas.
    private func ridge(_ size: CGSize, _ p: [CGFloat]) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: p[0] * w, y: p[1] * h))
        var i = 2
        while i < p.count - 2 {
            let a = CGPoint(x: p[i] * w, y: p[i + 1] * h)
            let b = CGPoint(x: p[i + 2] * w, y: p[i + 3] * h)
            path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            i += 2
        }
        path.addLine(to: CGPoint(x: p[p.count - 2] * w, y: p[p.count - 1] * h))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }

    /// Two fluted columns carrying a broken entablature.
    private func colonnade(_ ctx: GraphicsContext, _ size: CGSize, _ color: Color) {
        let h = size.height
        let cw = h * 0.105
        let top = h * 0.20
        let x0 = h * 0.10
        let gap = cw * 2.05
        let flute = Palette.bg.opacity(0.55)
        for k in 0..<2 {
            let x = x0 + CGFloat(k) * gap
            ctx.fill(Path(CGRect(x: x - cw * 0.22, y: top, width: cw * 1.44, height: h * 0.022)), with: .color(color))
            ctx.fill(Path(CGRect(x: x - cw * 0.10, y: top + h * 0.022, width: cw * 1.20, height: h * 0.024)), with: .color(color))
            ctx.fill(Path(CGRect(x: x, y: top + h * 0.046, width: cw, height: h - top - h * 0.046)), with: .color(color))
            for f in 1...3 {
                let fx = x + cw * CGFloat(f) / 4
                var line = Path()
                line.move(to: CGPoint(x: fx, y: top + h * 0.06))
                line.addLine(to: CGPoint(x: fx, y: h))
                ctx.stroke(line, with: .color(flute), lineWidth: cw * 0.05)
            }
        }
        let left = x0 - cw * 0.34
        let right = x0 + gap + cw * 1.50
        var beam = Path()
        beam.move(to: CGPoint(x: left, y: top))
        beam.addLine(to: CGPoint(x: left, y: top - h * 0.085))
        beam.addLine(to: CGPoint(x: right - cw * 0.50, y: top - h * 0.085))
        beam.addLine(to: CGPoint(x: right - cw * 0.34, y: top - h * 0.052))
        beam.addLine(to: CGPoint(x: right - cw * 0.10, y: top - h * 0.040))
        beam.addLine(to: CGPoint(x: right, y: top))
        beam.closeSubpath()
        ctx.fill(beam, with: .color(color))
        ctx.fill(Path(CGRect(x: left - cw * 0.16, y: top - h * 0.110, width: gap + cw * 0.9, height: h * 0.025)), with: .color(color))
    }

    /// A windswept maple on a rock: dark trunk, layered pads of red leaves.
    private func maple(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width
        let h = size.height
        // Anchored to the right edge and scaled by the height; a little low, clear of the header.
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: w - (1 - fx) * h * 1.9, y: (fy + 0.10) * h)
        }

        var cliff = Path()
        cliff.move(to: pt(0.52, 1))
        cliff.addQuadCurve(to: pt(0.70, 0.84), control: pt(0.60, 0.86))
        cliff.addQuadCurve(to: pt(0.88, 0.80), control: pt(0.80, 0.76))
        cliff.addQuadCurve(to: pt(1.02, 0.74), control: pt(0.95, 0.72))
        cliff.addLine(to: pt(1.02, 1))
        cliff.closeSubpath()
        ctx.fill(cliff, with: .color(Palette.rock))

        func limb(_ width: CGFloat, _ p: [CGFloat]) {
            var path = Path()
            path.move(to: pt(p[0], p[1]))
            path.addCurve(to: pt(p[6], p[7]), control1: pt(p[2], p[3]), control2: pt(p[4], p[5]))
            ctx.stroke(path, with: .color(Palette.trunk), style: StrokeStyle(lineWidth: h * width, lineCap: .round))
        }
        limb(0.034, [0.84, 0.80, 0.80, 0.66, 0.90, 0.58, 0.82, 0.46])
        limb(0.022, [0.82, 0.46, 0.78, 0.38, 0.72, 0.38, 0.66, 0.33])
        limb(0.018, [0.84, 0.56, 0.92, 0.50, 0.94, 0.44, 0.97, 0.38])
        limb(0.014, [0.80, 0.42, 0.84, 0.34, 0.86, 0.30, 0.84, 0.22])
        limb(0.012, [0.83, 0.62, 0.76, 0.58, 0.72, 0.60, 0.68, 0.56])

        func pad(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ light: Bool) {
            for k in -2...2 {
                let a = CGFloat(abs(k))
                let base = pt(cx, cy)
                let center = CGPoint(x: base.x + CGFloat(k) * h * r * 0.42, y: base.y - h * (2 - a) * r * 0.16)
                let lighter = ((k + 2) % 2 == 0) == light
                ctx.fill(circle(center, h * r * (0.42 - a * 0.05)), with: .color((lighter ? Palette.leafLight : Palette.leaf).opacity(0.92)))
            }
        }
        pad(0.66, 0.31, 0.17, false)
        pad(0.84, 0.20, 0.19, true)
        pad(0.97, 0.35, 0.16, false)
        pad(0.78, 0.38, 0.14, true)
        pad(0.68, 0.54, 0.11, false)
        pad(0.90, 0.47, 0.10, true)
    }
}
