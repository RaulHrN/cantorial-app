import AVFoundation
import CantorialCore
import SwiftUI
import UIKit

/// The big note name with its octave.
struct NoteReadout: View {
    let note: Int
    let naming: Naming
    var large = true

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if note < 0 {
                Text("—").font(.system(size: large ? 104 : 62, weight: .light)).foregroundStyle(Palette.faint)
            } else {
                Text(NoteNames.name(note, naming))
                    .font(.system(size: large ? 104 : 62, weight: .light))
                    .tracking(-3)
                    .foregroundStyle(Palette.text)
                Text("\(NoteNames.octave(note))")
                    .font(large ? Typo.title : Typo.heading)
                    .foregroundStyle(Palette.muted)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: large ? .infinity : nil)
    }
}

/// Horizontal tuning meter, -50...+50 cents, redrawn every display frame.
struct CentsMeter: View {
    let cents: () -> Float
    let active: () -> Bool
    var running = true

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { _ in
            Canvas { ctx, size in
                let pad: CGFloat = 10
                let half = size.width / 2 - pad
                let mid = size.width / 2
                let y = size.height / 2
                var base = Path()
                base.move(to: CGPoint(x: pad, y: y))
                base.addLine(to: CGPoint(x: size.width - pad, y: y))
                ctx.stroke(base, with: .color(Palette.line), lineWidth: 1)
                for k in stride(from: -50, through: 50, by: 10) {
                    let x = mid + CGFloat(k) / 50 * half
                    let len: CGFloat = k == 0 ? 14 : (abs(k) == 50 ? 8 : 4)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: y - len))
                    tick.addLine(to: CGPoint(x: x, y: y + len))
                    ctx.stroke(tick, with: .color(k == 0 ? Palette.muted : Palette.line), lineWidth: 1.5)
                }
                if active() {
                    let v = min(max(cents(), -50), 50)
                    let color = abs(v) <= 10 ? Palette.accent : (abs(v) <= 25 ? Palette.warn : Palette.bad)
                    let x = mid + CGFloat(v) / 50 * half
                    var bar = Path()
                    bar.move(to: CGPoint(x: mid, y: y))
                    bar.addLine(to: CGPoint(x: x, y: y))
                    ctx.stroke(bar, with: .color(color), lineWidth: 3)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16)), with: .color(color))
                }
            }
        }
        .frame(height: 40)
    }
}

/// Thin input level bar.
struct LevelBar: View {
    let level: () -> Float
    var running = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { _ in
            Canvas { ctx, size in
                let f = CGFloat(min(max((level() + 60) / 50, 0), 1))
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2), with: .color(Palette.surface2))
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width * f, height: size.height), cornerRadius: 2), with: .color(Palette.muted))
            }
        }
        .frame(height: 4)
    }
}

/// Backing balance meter: your level relative to the lead-voice reference, from -18 to +4 dB,
/// with the recommended zone (`target` ± 2.5 dB) highlighted.
struct BalanceMeter: View {
    let relative: () -> Float
    let target: Float
    var running = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { _ in
            Canvas { ctx, size in
                let lo: Float = -18
                let hi: Float = 4
                func x(_ db: Float) -> CGFloat { CGFloat((min(max(db, lo), hi) - lo) / (hi - lo)) * size.width }
                let y = size.height / 2
                func line(_ a: CGFloat, _ b: CGFloat, _ color: Color, _ width: CGFloat) {
                    var p = Path()
                    p.move(to: CGPoint(x: a, y: y))
                    p.addLine(to: CGPoint(x: b, y: y))
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                line(0, size.width, Palette.line, 4)
                line(x(target - 2.5), x(target + 2.5), Palette.accent.opacity(0.35), 10)
                var zero = Path()
                zero.move(to: CGPoint(x: x(0), y: y - 9))
                zero.addLine(to: CGPoint(x: x(0), y: y + 9))
                ctx.stroke(zero, with: .color(Palette.muted), lineWidth: 1.5)
                let v = relative()
                if !v.isNaN {
                    let ok = abs(v - target) <= 2.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x(v) - 7, y: y - 7, width: 14, height: 14)), with: .color(ok ? Palette.accent : Palette.warn))
                }
            }
        }
        .frame(height: 28)
    }
}

/// Words for where the singer is compared to the balance target.
func balanceHint(_ relative: Float, _ target: Float) -> String {
    if relative.isNaN { return "cante para medir" }
    if relative - target > 2.5 { return "mais suave" }
    if target - relative > 2.5 { return "um pouco mais forte" }
    return "na medida"
}

/// One-line warning shown while practising with sound through the speaker.
struct SpeakerWarning: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "headphones").font(.system(size: 13))
            Text("Sem fones o microfone também ouve a música e pode confundir instrumento com voz.")
                .font(Typo.small)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.warn)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows `content` only once microphone access is granted; otherwise explains and asks.
struct MicGate<Content: View>: View {
    @ViewBuilder var content: Content
    @State var permission = AVAudioApplication.shared.recordPermission
    @Environment(\.scenePhase) var scenePhase

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if permission == .granted {
                content
            } else {
                VStack(spacing: 0) {
                    Spacer()
                    Image(systemName: "mic.fill").font(.system(size: 36)).foregroundStyle(Palette.accent)
                    Text("Preciso ouvir sua voz").font(Typo.heading).foregroundStyle(Palette.text).padding(.top, 16)
                    Text("O som é analisado no próprio iPhone e nunca é gravado nem enviado para a internet.")
                        .font(Typo.small)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    Group {
                        if permission == .denied {
                            PillButton("Abrir Ajustes", icon: "gearshape") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        } else {
                            PillButton("Permitir microfone", icon: "mic") {
                                Task {
                                    _ = await AVAudioApplication.requestRecordPermission()
                                    permission = AVAudioApplication.shared.recordPermission
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 280)
                    .padding(.top, 20)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permission = AVAudioApplication.shared.recordPermission }
        }
    }
}

/// Keeps the microphone running while a screen wants it.
final class MicHold {
    private var held = false

    func set(_ want: Bool) {
        if want && !held {
            MicEngine.shared.acquire()
            held = true
        } else if !want && held {
            MicEngine.shared.release()
            held = false
        }
    }

    deinit { if held { MicEngine.shared.release() } }
}
