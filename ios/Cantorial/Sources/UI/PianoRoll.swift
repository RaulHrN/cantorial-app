import CantorialCore
import SwiftUI

/// guide: notes to listen to; melody: the lead; part: another harmony part; target: what you sing.
enum RollKind { case guide, melody, part, target }

struct RollNote {
    let startMs: Int
    let durMs: Int
    let midi: Int
    let kind: RollKind
    var target = -1

    var endMs: Int { startMs + durMs }
}

/// Ring buffer of sung pitch points in timeline time. Written and drawn on the main thread.
final class Trace {
    private let capacity: Int
    private var time: [Float]
    private var midi: [Float]
    private var start = 0
    private(set) var count = 0

    init(capacity: Int = 720) {
        self.capacity = capacity
        time = [Float](repeating: 0, count: capacity)
        midi = [Float](repeating: .nan, count: capacity)
    }

    func add(_ t: Float, _ m: Float) {
        let i = (start + count) % capacity
        if count < capacity { count += 1 } else { start = (start + 1) % capacity }
        time[i] = t
        midi[i] = m
    }

    func clear() {
        start = 0
        count = 0
    }

    func forEach(_ body: (Float, Float) -> Void) {
        for k in 0..<count {
            let i = (start + k) % capacity
            body(time[i], midi[i])
        }
    }
}

/// Smoothly follows the pitch range that should be visible, so the grid glides instead of jumping.
final class RangeFollower {
    private(set) var lo: Float = .nan
    private(set) var hi: Float = .nan

    func update(_ targetLo: Float, _ targetHi: Float, minSpan: Float = 12) {
        var a = targetLo - 2.5
        var b = targetHi + 2.5
        if b - a < minSpan {
            let mid = (a + b) / 2
            a = mid - minSpan / 2
            b = mid + minSpan / 2
        }
        if lo.isNaN {
            lo = a
            hi = b
        } else {
            lo += (a - lo) * 0.08
            hi += (b - hi) * 0.08
        }
    }

    var center: Float { lo.isNaN ? 60 : (lo + hi) / 2 }
}

private let natural: [Bool] = [true, false, true, false, true, true, false, true, false, true, false, true]

private func drawGrid(_ ctx: GraphicsContext, _ size: CGSize, _ range: RangeFollower, _ naming: Naming, _ flats: Bool) {
    let lo = range.lo
    let hi = range.hi
    let h = size.height
    let rowH = h / CGFloat(hi - lo)
    let showAll = rowH > 11
    for m in Int(lo.rounded(.up))...Int(hi.rounded(.down)) {
        let y = h - CGFloat((Float(m) - lo) / (hi - lo)) * h
        let pc = floorMod(m, 12)
        let strong = pc == 0
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y))
        p.addLine(to: CGPoint(x: size.width, y: y))
        let alpha = strong ? 1.0 : (natural[pc] ? 0.55 : 0.25)
        ctx.stroke(p, with: .color(Palette.line.opacity(alpha)), lineWidth: 1)
        if strong || (showAll && natural[pc]) {
            let label = strong ? NoteNames.full(m, naming, flats: flats) : NoteNames.name(m, naming, flats: flats)
            ctx.draw(Text(label).font(.system(size: 10)).foregroundColor(Palette.muted), at: CGPoint(x: 4, y: y - 3), anchor: .bottomLeading)
        }
    }
}

/// Scrolling piano roll: notes as bars, the singer's pitch as a line and a fixed playhead.
/// Redrawn on every display frame while `running`.
struct PianoRoll: View {
    let notes: [RollNote]
    let clock: () -> Float
    var trace: Trace?
    var naming: Naming = .solfege
    var flats = false
    var windowMs: Float = 6000
    var playhead: Float = 0.3
    var accuracy: ((Int) -> Float)?
    var selected = -1
    /// Shown when no note is near the playhead, e.g. "trecho instrumental".
    var emptyLabel: String?
    var running = true
    var onTap: ((Float, Float) -> Void)?
    var onScrub: ((Float) -> Void)?

    @State var range = RangeFollower()
    @State var lastDrag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: !running)) { _ in
                Canvas { ctx, size in draw(ctx, size) }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(geo.size), including: onScrub == nil ? .none : .all)
            .simultaneousGesture(tapGesture(geo.size), including: onTap == nil ? .none : .all)
        }
    }

    private func tapGesture(_ size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let onTap, !range.lo.isNaN, size.width > 0 else { return }
            let w = Float(size.width)
            let h = Float(size.height)
            let time = clock() + (Float(value.location.x) - w * playhead) / w * windowMs
            let midi = range.lo + (h - Float(value.location.y)) / h * (range.hi - range.lo)
            onTap(time, midi)
        }
    }

    private func scrubGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = value.translation.width - lastDrag
                lastDrag = value.translation.width
                if size.width > 0 { onScrub?(-Float(dx / size.width) * windowMs) }
            }
            .onEnded { _ in lastDrag = 0 }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let t = clock()
        let w = Float(size.width)
        let h = Float(size.height)
        guard w > 0, h > 0 else { return }
        let px = w * playhead
        let tStart = t - windowMs * playhead
        let tEnd = tStart + windowMs

        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        for n in notes where !(Float(n.endMs) < tStart - 1500 || Float(n.startMs) > tEnd + 1500) {
            lo = min(lo, Float(n.midi))
            hi = max(hi, Float(n.midi))
        }
        trace?.forEach { tt, m in
            if tt >= tStart && !m.isNaN {
                lo = min(lo, m)
                hi = max(hi, m)
            }
        }
        if lo > hi {
            lo = range.center
            hi = lo
        }
        range.update(lo, hi)
        drawGrid(ctx, size, range, naming, flats)
        let rLo = range.lo
        let span = range.hi - range.lo
        let rowH = h / span
        let barH = min(max(rowH * 0.5, 6), 14)

        func x(_ ms: Float) -> CGFloat { CGFloat(px + (ms - t) / windowMs * w) }
        func y(_ midi: Float) -> CGFloat { CGFloat(h - (midi - rLo) / span * h) }

        for n in notes {
            let x0 = x(Float(n.startMs))
            let x1 = x(Float(n.endMs))
            if x1 < 0 || x0 > CGFloat(w) { continue }
            let color: Color
            switch n.kind {
            case .guide: color = Palette.faint
            case .melody: color = Palette.melody.opacity(0.6)
            case .part: color = Palette.rose.opacity(0.6)
            case .target:
                let acc = (accuracy != nil && n.target >= 0) ? accuracy!(n.target) : -1
                if acc < 0 {
                    color = Palette.accent.opacity(Float(n.endMs) < t ? 0.5 : 0.9)
                } else if acc >= 0.7 {
                    color = Palette.accent
                } else if acc >= 0.4 {
                    color = Palette.warn
                } else {
                    color = Palette.bad
                }
            }
            let rect = CGRect(x: x0, y: y(Float(n.midi)) - CGFloat(barH) / 2, width: max(3, x1 - x0), height: CGFloat(barH))
            ctx.fill(Path(roundedRect: rect, cornerRadius: CGFloat(barH) / 2), with: .color(color))
        }
        if selected >= 0 && selected < notes.count {
            let n = notes[selected]
            let x0 = x(Float(n.startMs))
            let x1 = x(Float(n.endMs))
            let pad: CGFloat = 3
            let rect = CGRect(x: x0 - pad, y: y(Float(n.midi)) - CGFloat(barH) / 2 - pad, width: max(3, x1 - x0) + 2 * pad, height: CGFloat(barH) + 2 * pad)
            ctx.stroke(Path(roundedRect: rect, cornerRadius: CGFloat(barH) / 2 + pad), with: .color(Palette.text), lineWidth: 2)
        }

        var head = Path()
        head.move(to: CGPoint(x: CGFloat(px), y: 0))
        head.addLine(to: CGPoint(x: CGFloat(px), y: CGFloat(h)))
        ctx.stroke(head, with: .color(Palette.text.opacity(0.3)), lineWidth: 1)

        if let emptyLabel, !notes.isEmpty,
           !notes.contains(where: { Float($0.startMs) < t + 1600 && Float($0.endMs) > t - 400 }) {
            ctx.draw(Text(emptyLabel).font(Typo.label).foregroundColor(Palette.muted), at: CGPoint(x: CGFloat(w / 2), y: CGFloat(h / 2)))
        }

        if let trace {
            var path = Path()
            var pen = false
            var prevT: Float = 0
            var last = CGPoint.zero
            var lastT: Float = -1e9
            trace.forEach { tt, m in
                if tt < tStart - 200 || tt > t + 100 || m.isNaN || (pen && tt - prevT > 90) {
                    pen = false
                } else {
                    let p = CGPoint(x: x(tt), y: y(m))
                    if pen { path.addLine(to: p) } else { path.move(to: p) }
                    pen = true
                    last = p
                    lastT = tt
                }
                prevT = tt
            }
            ctx.stroke(path, with: .color(Palette.text), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if t - lastT < 200 {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(Palette.text))
            }
        }
    }
}

/// Live pitch line straight from the microphone ring buffer, newest at the right edge.
struct LiveTrace: View {
    var naming: Naming = .solfege
    var windowMs: Float = 5000
    var running = true

    @State var range = RangeFollower()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { _ in
            Canvas { ctx, size in draw(ctx, size) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let mic = MicEngine.shared
        let nowNs = HostClock.nowNs()
        let w = Float(size.width)
        let h = Float(size.height)
        guard w > 0, h > 0 else { return }
        let f = mic.frames
        let count = Int(min(f, min(Int64(windowMs / mic.hopMs) + 4, Int64(MicEngine.capacity - 1))))

        var lo = Float.greatestFiniteMagnitude
        var hi = -Float.greatestFiniteMagnitude
        for k in 0..<count {
            let m = mic.midi[mic.index(f - 1 - Int64(k))]
            if !m.isNaN {
                lo = min(lo, m)
                hi = max(hi, m)
            }
        }
        if lo > hi {
            lo = range.center
            hi = lo
        }
        range.update(lo, hi)
        drawGrid(ctx, size, range, naming, false)
        let rLo = range.lo
        let span = range.hi - range.lo

        var path = Path()
        var pen = false
        var last = CGPoint.zero
        for k in stride(from: count - 1, through: 0, by: -1) {
            let i = mic.index(f - 1 - Int64(k))
            let m = mic.midi[i]
            let age = Float(nowNs - mic.timeNs[i]) / 1e6
            if m.isNaN || age > windowMs {
                pen = false
                continue
            }
            let p = CGPoint(x: CGFloat(w - age / windowMs * w), y: CGFloat(h - (m - rLo) / span * h))
            if pen { path.addLine(to: p) } else { path.move(to: p) }
            pen = true
            last = p
        }
        ctx.stroke(path, with: .color(Palette.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        if count > 0 && !mic.midi[mic.index(f - 1)].isNaN {
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12)), with: .color(Palette.accent))
        }
    }
}
