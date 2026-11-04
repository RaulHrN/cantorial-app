import CantorialCore
import SwiftUI

struct ExerciseScreen: View {
    let id: String
    let lead: VoiceType?

    var body: some View {
        let ex = Content.exercise(id)
        Group {
            if let ex {
                MicGate {
                    switch ex.kind {
                    case .breath: BreathContent(ex: ex)
                    case .balance: BalanceContent(ex: ex)
                    default: PatternContent(ex: ex, lead: lead)
                    }
                }
            } else {
                Text("Exercício não encontrado.").font(Typo.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle(ex?.title ?? "Exercício")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum ExercisePhase: String {
    case idle = "Pronto?"
    case listen = "Ouça"
    case ready = "Prepare-se"
    case sing = "Sua vez"
    case paused = "Pausado"
    case done = "Concluído"
}

private func rollNotes(_ tl: Timeline) -> [RollNote] {
    var target = 0
    return tl.notes.map { n in
        switch n.role {
        case .listen: return RollNote(startMs: n.startMs, durMs: n.durMs, midi: n.midi, kind: .guide)
        case .accomp: return RollNote(startMs: n.startMs, durMs: n.durMs, midi: n.midi, kind: n.gain < 1 ? .part : .melody)
        case .target:
            defer { target += 1 }
            return RollNote(startMs: n.startMs, durMs: n.durMs, midi: n.midi, kind: .target, target: target)
        }
    }
}

/// Listen, then sing: repetitions of a pattern moving through the singer's range.
@Observable
final class PatternModel {
    let ex: Exercise
    let lead: VoiceType?
    let roots: [Int]
    private(set) var running = false
    private(set) var rep = 0
    var transpose = 0
    private(set) var phase: ExercisePhase = .idle
    private(set) var timeline: Timeline
    private(set) var results: [Float] = []
    private(set) var notes: [RollNote]
    private(set) var guide = false
    @ObservationIgnored private(set) var scorer: Scorer
    let trace = Trace()
    let synth = Synth()
    @ObservationIgnored private var guideTrack: SynthTrack?
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var listenEnd = 0
    private let range: ClosedRange<Int>

    init(ex: Exercise, lead: VoiceType?) {
        self.ex = ex
        self.lead = lead
        let prefs = Prefs.shared
        range = prefs.range
        roots = ExercisePlan.roots(ex, low: prefs.rangeLow, high: prefs.rangeHigh)
        let tl = ExerciseTimeline.build(ex, root: roots.first ?? 60, range: prefs.range, lead: lead)
        timeline = tl
        notes = rollNotes(tl)
        scorer = Scorer(tl.targets)
    }

    var currentRoot: Int { min(max(roots[min(rep, roots.count - 1)] + transpose, 24), 96) }

    func setGuide(_ on: Bool) {
        guide = on
        guideTrack?.enabled = on
    }

    func toggle() {
        if running {
            pause()
        } else {
            if rep >= roots.count {
                rep = 0
                results = []
            }
            running = true
            hold.set(true)
            startRep()
            let l = DisplayLink { [weak self] _ in self?.frame() }
            link = l
            l.start()
        }
    }

    func pause() {
        link?.stop()
        link = nil
        synth.stop()
        hold.set(false)
        running = false
        if phase != .done { phase = .paused }
    }

    func stop() {
        pause()
    }

    private func startRep() {
        synth.a4 = Prefs.shared.a4
        let tl = ExerciseTimeline.build(ex, root: currentRoot, range: range, lead: lead)
        timeline = tl
        notes = rollNotes(tl)
        scorer = Scorer(tl.targets)
        trace.clear()
        listenEnd = tl.notes.filter { $0.role == .listen }.map(\.endMs).max() ?? 0
        // One track per loudness, so backing parts are heard at their recommended balance.
        let heard = Dictionary(grouping: tl.notes.filter { $0.role != .target }, by: \.gain)
            .map { SynthTrack(timed: $0.value, gain: 0.3 * $0.key) }
        let g = SynthTrack(timed: tl.targets, gain: 0.2, bright: true)
        g.enabled = guide
        guideTrack = g
        synth.start(heard + [g], from: 0)
        lastFrame = MicEngine.shared.frames
    }

    private func frame() {
        let mic = MicEngine.shared
        let pos = synth.positionMs()
        let f = mic.frames
        let nowNs = HostClock.nowNs()
        var i = max(lastFrame, f - 64)
        while i < f {
            let idx = mic.index(i)
            let t = pos - Float(nowNs - mic.timeNs[idx]) / 1e6 - mic.latencyMs
            let m = mic.midi[idx]
            scorer.add(t, m)
            if t >= Float(listenEnd) { trace.add(t, m) }
            i += 1
        }
        lastFrame = f
        let p: ExercisePhase = pos < Float(listenEnd) ? .listen : (pos < Float(timeline.singStartMs) ? .ready : .sing)
        if p != phase { phase = p }
        if pos >= Float(timeline.lengthMs) {
            synth.stop()
            results.append(max(0, scorer.total()))
            rep += 1
            if rep < roots.count {
                startRep()
            } else {
                phase = .done
                pause()
            }
        }
    }
}

private struct PatternContent: View {
    let ex: Exercise
    let lead: VoiceType?
    @State var model: PatternModel?
    @State var showSteps = true
    var prefs = Prefs.shared
    var headphones = Headphones.shared

    var body: some View {
        VStack(spacing: 0) {
            if let model { content(model) }
        }
        .onAppear { if model == nil { model = PatternModel(ex: ex, lead: lead) } }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder
    private func content(_ model: PatternModel) -> some View {
        let naming = prefs.naming
        if ex.needsHeadphones && !headphones.connected { SpeakerWarning().padding(.bottom, 8) }
        Panel(action: { showSteps.toggle() }) {
            HStack {
                Caps("Como fazer")
                Spacer()
                Text(showSteps ? "ocultar" : "mostrar").font(Typo.small).foregroundStyle(Palette.muted)
            }
            if showSteps {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ex.steps, id: \.self) { Bullet(text: $0) }
                }
                .padding(.top, 8)
            }
        }
        HStack(alignment: .bottom) {
            Text(model.phase.rawValue).font(Typo.title).foregroundStyle(model.phase == .sing ? Palette.accent : Palette.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Tom \(NoteNames.full(model.currentRoot, naming))").font(Typo.label).foregroundStyle(Palette.text)
                Text("\(min(model.rep + 1, model.roots.count)) de \(model.roots.count)").font(Typo.small).foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 16)
        PianoRoll(
            notes: model.notes,
            clock: { model.synth.positionMs() },
            trace: model.trace,
            naming: naming,
            windowMs: 7000,
            playhead: 0.25,
            accuracy: { model.scorer.noteAccuracy($0) },
            running: model.running
        )
        .frame(maxHeight: .infinity)
        .padding(.vertical, 8)
        Group {
            if let last = model.results.last {
                let avg = model.results.reduce(0, +) / Float(model.results.count)
                Text("Última: \(Int((last * 100).rounded()))%   ·   Média: \(Int((avg * 100).rounded()))%")
            } else {
                Text("Ouça primeiro, depois cante quando a barra ficar colorida.")
            }
        }
        .font(Typo.small)
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity)
        HStack {
            Spacer()
            RoundButton(icon: "minus", label: "Tom abaixo", size: 48, primary: false) { model.transpose -= 1 }
            Spacer()
            RoundButton(icon: model.running ? "pause.fill" : "play.fill", label: model.running ? "Pausar" : "Começar", size: 72) { model.toggle() }
            Spacer()
            RoundButton(icon: "plus", label: "Tom acima", size: 48, primary: false) { model.transpose += 1 }
            Spacer()
        }
        .padding(.top, 12)
        ToggleRow(label: "Tocar o alvo enquanto canto", isOn: Binding(get: { model.guide }, set: { model.setGuide($0) }), detail: "Ajuda no começo. Use fones.")
            .padding(.bottom, 8)
    }
}

private let minBreath: Float = 0.42

/// 4 s in, 4 s hold, 8 s out on "sss", five times; the level meter judges how even the air is.
@Observable
final class BreathModel {
    let cycles = 5
    private(set) var running = false
    private(set) var cycle = 0
    private(set) var phaseName = "Pronto?"
    private(set) var seconds = 0
    private(set) var feedback = ""
    @ObservationIgnored private(set) var progress: Float = minBreath
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var t0: Double = 0
    @ObservationIgnored private var exhale: [Float] = []
    @ObservationIgnored private var lastFrame: Int64 = 0

    func toggle() {
        if running {
            pause()
            return
        }
        if cycle >= cycles {
            cycle = 0
            feedback = ""
        }
        running = true
        hold.set(true)
        t0 = HostClock.nowMs() - Double(cycle) * 16000
        lastFrame = MicEngine.shared.frames
        let l = DisplayLink { [weak self] _ in self?.frame() }
        link = l
        l.start()
    }

    func pause() {
        link?.stop()
        link = nil
        hold.set(false)
        running = false
        if cycle < cycles && phaseName != "Concluído" { phaseName = "Pausado" }
    }

    func reset() {
        pause()
        cycle = 0
        feedback = ""
        phaseName = "Pronto?"
        progress = minBreath
    }

    private func set(_ name: String, _ s: Int) {
        if phaseName != name { phaseName = name }
        if seconds != s { seconds = s }
    }

    private func frame() {
        let mic = MicEngine.shared
        let e = HostClock.nowMs() - t0 - Double(cycle) * 16000
        if e < 4000 {
            set("Inspire", 4 - Int(e / 1000))
            progress = minBreath + (1 - minBreath) * Float(e / 4000)
            exhale.removeAll(keepingCapacity: true)
        } else if e < 8000 {
            set("Segure", 4 - Int((e - 4000) / 1000))
            progress = 1
        } else if e < 16000 {
            set("Solte em \"sss\"", 8 - Int((e - 8000) / 1000))
            progress = 1 - (1 - minBreath) * Float((e - 8000) / 8000)
            let f = mic.frames
            var i = max(lastFrame, f - 64)
            while i < f {
                exhale.append(mic.levelDb[mic.index(i)])
                i += 1
            }
        } else {
            feedback = steadiness(exhale)
            cycle += 1
            if cycle >= cycles {
                phaseName = "Concluído"
                pause()
            }
        }
        lastFrame = mic.frames
    }

    /// Judges how even the "sss" was from the spread of the input level.
    private func steadiness(_ levels: [Float]) -> String {
        let loud = levels.filter { $0 > -55 }
        if loud.count < 20 { return "não ouvi o \"sss\"" }
        let mean = loud.reduce(0, +) / Float(loud.count)
        let sd = (loud.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(loud.count)).squareRoot()
        if sd < 2.5 { return "sopro bem constante" }
        if sd < 5 { return "quase constante" }
        return "sopro irregular"
    }
}

private struct BreathContent: View {
    let ex: Exercise
    @State var model = BreathModel()

    var body: some View {
        VStack(spacing: 0) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ex.steps, id: \.self) { Bullet(text: $0) }
                }
            }
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: !model.running)) { _ in
                    Canvas { ctx, size in
                        let r = min(size.width, size.height) / 2 * 0.9
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        func circle(_ radius: CGFloat) -> Path {
                            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                        }
                        ctx.stroke(circle(r), with: .color(Palette.line), lineWidth: 1)
                        let p = r * CGFloat(model.progress)
                        ctx.fill(circle(p), with: .color(Palette.accent.opacity(0.12)))
                        ctx.stroke(circle(p), with: .color(Palette.accent), lineWidth: 2)
                    }
                }
                VStack {
                    Text(model.phaseName).font(Typo.title).foregroundStyle(Palette.text)
                    if model.running { Text("\(model.seconds)").font(Typo.heading).foregroundStyle(Palette.muted) }
                }
            }
            .frame(maxHeight: .infinity)
            Text("Ciclo \(min(model.cycle + 1, model.cycles)) de \(model.cycles)" + (model.feedback.isEmpty ? "" : "  ·  \(model.feedback)"))
                .font(Typo.small)
                .foregroundStyle(Palette.muted)
            LevelBar(level: { MicEngine.shared.latestLevel() }, running: model.running).padding(.vertical, 8)
            RoundButton(icon: model.running ? "pause.fill" : "play.fill", label: model.running ? "Pausar" : "Começar", size: 72) { model.toggle() }
                .padding(.top, 8)
            LinkText("Recomeçar", color: Palette.muted) { model.reset() }.padding(.vertical, 8)
        }
        .onDisappear { model.pause() }
    }
}

private let balanceSteps: [(name: String, target: Float, hint: String)] = [
    ("Backing", -6, "Volume de harmonia: a melodia na frente, você logo atrás."),
    ("Pad", -10, "Bem suave, como um tapete de som em \"Uh\"."),
    ("Resposta", -3, "Quase no volume do regente: a resposta entra quando ele para."),
]

/// Records the lead-voice reference level, then trains singing 6, 10 and 3 dB below it.
@Observable
final class BalanceModel {
    private(set) var step = 0
    private(set) var recording = false
    private(set) var reference = Prefs.shared.leadLevelDb
    private(set) var relativeText: Float = .nan
    @ObservationIgnored private(set) var relative: Float = .nan
    @ObservationIgnored private(set) var progress: Float = 0
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var voiced: [Float] = []
    @ObservationIgnored private var smooth: Float = .nan
    @ObservationIgnored private var lastVoicedMs: Double = 0
    @ObservationIgnored private var held: Float = 0
    @ObservationIgnored private var lastMs: Double = 0
    @ObservationIgnored private var lastUi: Double = 0

    var listening: Bool { recording || (1...balanceSteps.count).contains(step) }

    func record() {
        recording = true
        begin()
    }

    func restart() {
        end()
        step = 0
        recording = false
    }

    func end() {
        link?.stop()
        link = nil
        hold.set(false)
    }

    private func begin() {
        hold.set(true)
        lastFrame = MicEngine.shared.frames
        voiced = []
        smooth = .nan
        held = 0
        progress = 0
        lastMs = HostClock.nowMs()
        if link == nil {
            let l = DisplayLink { [weak self] _ in self?.frame() }
            link = l
            l.start()
        }
    }

    private func frame() {
        let mic = MicEngine.shared
        let now = HostClock.nowMs()
        let dt = Float((now - lastMs) / 1000)
        lastMs = now
        let f = mic.frames
        var i = max(lastFrame, f - 64)
        var any = false
        while i < f {
            let idx = mic.index(i)
            if !mic.midi[idx].isNaN {
                let db = mic.levelDb[idx]
                voiced.append(db)
                smooth = smooth.isNaN ? db : smooth + (db - smooth) * 0.15
                any = true
                lastVoicedMs = now
            }
            i += 1
        }
        lastFrame = f
        if now - lastVoicedMs > 500 { smooth = .nan }
        var done = false
        if step == 0 {
            // About three seconds of singing at lead volume.
            progress = min(Float(voiced.count) / 130, 1)
            done = voiced.count >= 130
        } else {
            let target = balanceSteps[step - 1].target
            relative = smooth.isNaN ? .nan : smooth - reference
            if any && abs(smooth - reference - target) <= 2.5 { held += dt }
            progress = min(held / 2.5, 1)
            done = held >= 2.5
        }
        if now - lastUi > 120 {
            lastUi = now
            if !(relativeText.isNaN && relative.isNaN) && relativeText != relative { relativeText = relative }
        }
        if !done { return }
        if step == 0 {
            let sorted = voiced.sorted()
            reference = sorted[sorted.count / 2]
            Prefs.shared.leadLevelDb = reference
            recording = false
        }
        step += 1
        relative = .nan
        relativeText = .nan
        if step <= balanceSteps.count {
            begin()
        } else {
            end()
        }
    }
}

private struct BalanceContent: View {
    let ex: Exercise
    @State var model = BalanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ex.steps, id: \.self) { Bullet(text: $0) }
                }
            }
            .padding(.bottom, 20)
            if model.step == 0 {
                Text("1. Volume de regente").font(Typo.title).foregroundStyle(Palette.text)
                Text("Cante \"aah\" numa nota confortável, forte e firme, como se fosse a voz principal.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.muted)
                if model.recording {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { _ in ProgressLine(value: model.progress) }
                        .padding(.top, 16)
                    Text("Ouvindo…").font(Typo.small).foregroundStyle(Palette.muted).padding(.top, 8)
                }
                Spacer()
                if !model.recording {
                    PillButton("Gravar referência", icon: "mic") { model.record() }
                }
            } else if model.step <= balanceSteps.count {
                let s = balanceSteps[model.step - 1]
                Text("\(model.step + 1). \(s.name) (\(Int(s.target)) dB)").font(Typo.title).foregroundStyle(Palette.text)
                Text(s.hint).font(Typo.body).foregroundStyle(Palette.muted)
                BalanceMeter(relative: { model.relative }, target: s.target).padding(.top, 24)
                HStack {
                    Text("−18 dB")
                    Spacer()
                    Text("regente")
                }
                .font(Typo.small)
                .foregroundStyle(Palette.faint)
                .padding(.top, 4)
                let rel = model.relativeText
                let ok = !rel.isNaN && abs(rel - s.target) <= 2.5
                Text(rel.isNaN ? "—" : String(format: "%+.0f dB", rel))
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ok ? Palette.accent : Palette.text)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                Text(balanceHint(rel, s.target)).font(Typo.label).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { _ in ProgressLine(value: model.progress) }
                    .padding(.top, 16)
                Text("Segure na faixa por 2,5 segundos").font(Typo.small).foregroundStyle(Palette.muted).padding(.top, 4)
                Spacer()
            } else {
                Text("Pronto!").font(Typo.title).foregroundStyle(Palette.accent)
                Text("Você treinou os três níveis de backing. A sua referência de volume ficou salva e é usada no medidor de equilíbrio da prática de músicas.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.muted)
                Spacer()
            }
            if model.step > 0 {
                LinkText("Recomeçar", color: Palette.muted) { model.restart() }.frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
        .onDisappear { model.end() }
    }
}

/// Finds the lowest and highest notes the singer holds steadily.
@Observable
final class RangeTestModel {
    private(set) var step = 0
    var low = -1
    var high = -1
    private(set) var current = -1
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var follower = NoteFollower()
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var runNote = -1
    @ObservationIgnored private var runStart: Double = 0

    func go(_ s: Int) {
        step = s
        listen(s == 1 || s == 2)
    }

    func listen(_ on: Bool) {
        if on && link == nil {
            hold.set(true)
            follower = NoteFollower()
            lastFrame = MicEngine.shared.frames
            let l = DisplayLink { [weak self] _ in self?.frame() }
            link = l
            l.start()
        } else if !on {
            link?.stop()
            link = nil
            hold.set(false)
        }
    }

    private func frame() {
        let mic = MicEngine.shared
        let f = mic.frames
        var i = max(lastFrame, f - 32)
        while i < f {
            let idx = mic.index(i)
            let m = mic.midi[idx]
            let ms = Double(mic.timeNs[idx]) / 1e6
            follower.update(m, nowMs: ms)
            if m.isNaN {
                runNote = -1
            } else {
                let r = Int(m.rounded())
                if r == runNote && abs(m - Float(r)) < 0.45 {
                    // A note counts once it is held steadily for 0.4 s.
                    if ms - runStart >= 400 {
                        if step == 1 && (low < 0 || r < low) { low = r }
                        if step == 2 && (high < 0 || r > high) { high = r }
                    }
                } else {
                    runNote = r
                    runStart = ms
                }
            }
            i += 1
        }
        lastFrame = f
        if current != follower.note { current = follower.note }
    }
}

struct RangeTestScreen: View {
    @Environment(Nav.self) var nav
    @State var model = RangeTestModel()
    var prefs = Prefs.shared

    var body: some View {
        MicGate { content }
            .padding(.horizontal, screenPadding)
            .navigationTitle("Teste de extensão")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { model.listen(false) }
    }

    @ViewBuilder
    private var content: some View {
        let naming = prefs.naming
        VStack(alignment: .leading, spacing: 0) {
            switch model.step {
            case 0:
                Panel {
                    Text("Vamos descobrir as notas mais grave e mais aguda que você canta com conforto.").font(Typo.body).foregroundStyle(Palette.text)
                    Text("Fique num lugar silencioso. Cante em \"a\" ou \"u\", sem forçar, e sustente cada nota por um segundo. Só contam notas firmes.")
                        .font(Typo.small)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 10)
                }
                Spacer()
                PillButton("Começar") { model.go(1) }.padding(.bottom, 16)
            case 1, 2:
                let first = model.step == 1
                let record = first ? model.low : model.high
                Text(first ? "Desça até a nota mais GRAVE" : "Agora suba até a mais AGUDA").font(Typo.heading).foregroundStyle(Palette.text)
                Text(first ? "Vá descendo devagar, nota por nota, até onde a voz ainda soa limpa." : "Suba devagar. Pode usar voz leve ou falsete, mas sem gritar.")
                    .font(Typo.small)
                    .foregroundStyle(Palette.muted)
                NoteReadout(note: model.current, naming: naming).padding(.top, 12)
                Text(record < 0 ? "Sustente uma nota…" : (first ? "Mais grave: " : "Mais aguda: ") + NoteNames.full(record, naming))
                    .font(Typo.label)
                    .foregroundStyle(record < 0 ? Palette.muted : Palette.accent)
                    .frame(maxWidth: .infinity)
                LiveTrace(naming: naming).frame(maxHeight: .infinity).padding(.vertical, 12)
                HStack(spacing: 12) {
                    PillButton("Refazer", primary: false) {
                        if first { model.low = -1 } else { model.high = -1 }
                    }
                    PillButton(first ? "Próximo" : "Ver resultado", enabled: record >= 0) { model.go(model.step + 1) }
                }
                .padding(.bottom, 16)
            default:
                result(naming)
            }
        }
    }

    @ViewBuilder
    private func result(_ naming: Naming) -> some View {
        let low = model.low
        let high = model.high
        if low >= 0 && high >= 0 && high - low >= 5 {
            let type = VoiceType.classify(low, high)
            let span = high - low
            Panel {
                Caps("Sua extensão")
                Text("\(NoteNames.full(low, naming)) – \(NoteNames.full(high, naming))").font(Typo.title).foregroundStyle(Palette.text).padding(.top, 6)
                Text("\(span) semitons" + (span >= 12 ? " · \(decimal(Float(span) / 12)) oitavas" : "")).font(Typo.small).foregroundStyle(Palette.muted)
                Caps("Voz provável").padding(.top, 16)
                Text(type.label).font(Typo.heading).foregroundStyle(Palette.accent).padding(.top, 6)
                Text("Faixa típica: \(NoteNames.full(type.low, naming)) – \(NoteNames.full(type.high, naming)). É só uma referência: timbre e conforto também contam, e a extensão cresce com treino.")
                    .font(Typo.small)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            PillButton("Salvar e usar nos exercícios") {
                prefs.setRange(low, high, measured: true)
                nav.pop()
            }
        } else {
            Panel {
                Text("Não consegui medir uma extensão confiável.").font(Typo.body).foregroundStyle(Palette.text)
                Text("Tente de novo num lugar mais silencioso, sustentando bem cada nota.").font(Typo.small).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        PillButton("Refazer o teste", primary: false) {
            model.low = -1
            model.high = -1
            model.go(1)
        }
        .padding(.vertical, 12)
    }
}
