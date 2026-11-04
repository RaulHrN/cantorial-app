import CantorialCore
import SwiftUI

/// What the practice is set up to sing; saved with the song.
struct PracticeConfig: Equatable {
    var key: Key
    var mode: HarmonyMode
    var octave: Int
    var backingMode: Bool
    var leadVoice: VoiceType
    var style: BackingStyle
    var voices: Int
    var part: Int
}

/// The lines of one practice setup: the lead, the part you sing and an optional other part.
struct PracticeLines {
    let lead: [NoteEvent]
    let mine: [NoteEvent]
    let other: [NoteEvent]
    let mineDb: Float
    let otherDb: Float
    let plan: BackingPlan?
}

@Observable
final class PracticeModel {
    static let speeds: [Float] = [0.5, 0.75, 1]

    let songId: String
    let title: String
    private(set) var notes: [NoteEvent]
    private(set) var config: PracticeConfig
    private(set) var lines: PracticeLines
    private(set) var roll: [RollNote] = []
    private(set) var phrases: [Phrase] = []
    private(set) var totalMs: Float = 0
    private(set) var playing = false
    private(set) var sliderPos: Float = 0
    private(set) var speed: Float = 1
    private(set) var music: StemPlayer.Mix? = .original
    private(set) var leadOn: Bool
    private(set) var mineOn = true
    private(set) var otherOn = true
    var loop = false
    private(set) var phraseIndex = 0
    private(set) var accuracy = -1
    private(set) var editing = false
    private(set) var selected = -1
    var confirmPhraseDelete = false
    private(set) var calibrating = false
    private(set) var calibration: Float = 0
    /// 0 loading, 1 ready, 2 failed, -1 no audio.
    private(set) var playerState: Int
    private(set) var relativeText: Float = .nan
    @ObservationIgnored private(set) var relative: Float = .nan
    @ObservationIgnored private(set) var scorer = Scorer([])
    let trace = Trace()
    let synth = Synth()
    let player: StemPlayer?
    @ObservationIgnored private var leadTrack = SynthTrack([], gain: 0)
    @ObservationIgnored private var mineTrack = SynthTrack([], gain: 0)
    @ObservationIgnored private var otherTrack = SynthTrack([], gain: 0)
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var pausedAt: Float = 0
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var lastUi: Double = 0
    @ObservationIgnored private var smooth: Float = .nan
    @ObservationIgnored private var lastVoiced: Double = 0
    @ObservationIgnored private var calibrationLevels: [Float] = []

    init(song: Song) {
        songId = song.id
        title = song.title
        notes = song.notes
        let prefs = Prefs.shared
        config = PracticeConfig(
            key: song.key, mode: song.mode, octave: song.octave, backingMode: song.backingMode,
            leadVoice: song.leadVoice ?? prefs.voiceType, style: song.backingStyle,
            voices: song.backingVoices, part: song.backingPart
        )
        lines = PracticeLines(lead: [], mine: [], other: [], mineDb: 0, otherDb: 0, plan: nil)
        player = song.audioURL.map { StemPlayer(url: $0) }
        playerState = player == nil ? -1 : 0
        leadOn = song.audioURL == nil
        totalMs = Float(max(song.durationMs, song.notes.last?.endMs ?? 0))
        rebuild()
        player?.prepare { [weak self] in
            guard let self else { return }
            self.playerState = 1
            self.applyMix()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.checkPlayer() }
    }

    private func checkPlayer() {
        guard let player, playerState == 0 else { return }
        if player.failed {
            playerState = 2
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkPlayer() }
        }
    }

    var singer: ClosedRange<Int> { Prefs.shared.range }

    private var useAudio: Bool { player != nil && playerState == 1 }

    // MARK: settings

    func change(_ edit: (inout PracticeConfig) -> Void) {
        var c = config
        edit(&c)
        if c == config { return }
        config = c
        rebuild()
        persist()
    }

    private func persist() {
        guard var song = SongStore.shared.find(songId) else { return }
        song.key = config.key
        song.mode = config.mode
        song.octave = config.octave
        song.backingMode = config.backingMode
        song.leadVoice = config.leadVoice
        song.backingStyle = config.style
        song.backingVoices = config.voices
        song.backingPart = config.part
        song.notes = notes
        SongStore.shared.upsert(song)
    }

    /// Recomputes the lines after a change of settings, notes or vocal range.
    func rebuild() {
        let c = config
        if !c.backingMode {
            let mine = Harmony.voice(notes, key: c.key, mode: c.mode, octaveShift: c.octave * 12, range: singer)
            lines = PracticeLines(lead: notes, mine: mine, other: [], mineDb: 0, otherDb: 0, plan: nil)
        } else {
            let plan = Backing.arrange(notes, key: c.key, style: c.style, lead: c.leadVoice, singer: singer, voices: c.voices)
            let index = min(max(c.part, 0), max(0, plan.parts.count - 1))
            let mine = plan.parts.isEmpty ? nil : plan.parts[index]
            let other = plan.parts.enumerated().first { $0.offset != index }?.element
            lines = PracticeLines(
                lead: plan.lead, mine: mine?.notes ?? [], other: other?.notes ?? [],
                mineDb: mine?.gainDb ?? 0, otherDb: other?.gainDb ?? 0, plan: plan
            )
        }
        scorer = Scorer(lines.mine.map { TimedNote($0.startMs, $0.durMs, $0.midi, .target) })
        var r = lines.lead.map { RollNote(startMs: $0.startMs, durMs: $0.durMs, midi: $0.midi, kind: .melody) }
        r += lines.other.map { RollNote(startMs: $0.startMs, durMs: $0.durMs, midi: $0.midi, kind: .part) }
        r += lines.mine.enumerated().map { RollNote(startMs: $0.element.startMs, durMs: $0.element.durMs, midi: $0.element.midi, kind: .target, target: $0.offset) }
        roll = r
        phrases = Phrases.split(notes)
        accuracy = -1
        let base: Float = 0.26
        leadTrack = SynthTrack(lines.lead, gain: base)
        // In backing mode the guide is heard at the recommended balance against the lead.
        mineTrack = SynthTrack(lines.mine, gain: c.backingMode ? base * dbToGain(lines.mineDb) * 1.4 : 0.24, bright: true)
        otherTrack = SynthTrack(lines.other, gain: base * dbToGain(lines.otherDb) * 1.4)
        applyToggles()
        if playing { synth.start([leadTrack, otherTrack, mineTrack], from: now(), speed: speed) }
    }

    private func applyToggles() {
        leadTrack.enabled = leadOn
        mineTrack.enabled = mineOn
        otherTrack.enabled = otherOn
    }

    private func applyMix() {
        player?.setVolume(music != nil ? 1 : 0)
        player?.mix = music ?? .original
    }

    func toggleLead() { leadOn.toggle(); applyToggles() }
    func toggleMine() { mineOn.toggle(); applyToggles() }
    func toggleOther() { otherOn.toggle(); applyToggles() }

    /// Original → Sem voz (stereo only) → Voz em destaque → off → Original.
    func nextMix() {
        switch music {
        case .original: music = (player?.stereo ?? true) ? .instrumental : .voice
        case .instrumental: music = .voice
        case .voice: music = nil
        case nil: music = .original
        }
        applyMix()
    }

    func nextSpeed() {
        let i = PracticeModel.speeds.firstIndex(of: speed) ?? 2
        speed = PracticeModel.speeds[(i + 1) % PracticeModel.speeds.count]
        if playing { seek(now()) }
    }

    // MARK: transport

    func now() -> Float {
        if !playing { return pausedAt }
        return useAudio ? player!.positionMs() : synth.positionMs()
    }

    func togglePlay() { playing ? pause() : start(pausedAt) }

    func start(_ from: Float) {
        let f = min(max(from, 0), totalMs)
        synth.a4 = Prefs.shared.a4
        if useAudio { player!.play(fromMs: Int(f.rounded()), speed: speed) }
        synth.start([leadTrack, otherTrack, mineTrack], from: f, speed: speed)
        trace.clear()
        pausedAt = f
        playing = true
        hold.set(true)
        lastFrame = MicEngine.shared.frames
        startLink()
    }

    func pause() {
        pausedAt = now()
        playing = false
        player?.pause()
        synth.stop()
        sliderPos = pausedAt
        if !calibrating {
            hold.set(false)
            stopLink()
        }
    }

    func seek(_ to: Float) {
        let t = min(max(to, 0), totalMs)
        if playing {
            pause()
            start(t)
        } else {
            pausedAt = t
            sliderPos = t
            trace.clear()
        }
    }

    func restart() {
        scorer.reset()
        accuracy = -1
        phraseIndex = 0
        seek(0)
    }

    func goToPhrase(_ i: Int) {
        if phrases.isEmpty { return }
        phraseIndex = min(max(i, 0), phrases.count - 1)
        seek(max(0, Float(phrases[phraseIndex].startMs) - 800))
    }

    func close() {
        if playing { pause() }
        calibrating = false
        hold.set(false)
        stopLink()
        player?.release()
        synth.stop()
    }

    private func startLink() {
        if link != nil { return }
        let l = DisplayLink { [weak self] _ in self?.frame() }
        link = l
        l.start()
    }

    private func stopLink() {
        link?.stop()
        link = nil
    }

    private func frame() {
        let mic = MicEngine.shared
        let nowMs = HostClock.nowMs()
        let f = mic.frames
        if calibrating {
            var i = max(lastFrame, f - 64)
            while i < f {
                let idx = mic.index(i)
                if !mic.midi[idx].isNaN { calibrationLevels.append(mic.levelDb[idx]) }
                i += 1
            }
            calibration = Float(calibrationLevels.count) / 130
            if calibrationLevels.count >= 130 {
                let sorted = calibrationLevels.sorted()
                Prefs.shared.leadLevelDb = sorted[sorted.count / 2]
                calibrating = false
                if !playing {
                    hold.set(false)
                    stopLink()
                }
            }
            lastFrame = f
            return
        }
        guard playing else { return }
        let pos = now()
        let nowNs = HostClock.nowNs()
        var i = max(lastFrame, f - 64)
        while i < f {
            let idx = mic.index(i)
            let ageMs = Float(nowNs - mic.timeNs[idx]) / 1e6 + mic.latencyMs
            let t = pos - ageMs * speed
            let m = mic.midi[idx]
            scorer.add(t, m)
            trace.add(t, m)
            if !m.isNaN {
                let db = mic.levelDb[idx]
                smooth = smooth.isNaN ? db : smooth + (db - smooth) * 0.1
                lastVoiced = nowMs
            }
            i += 1
        }
        lastFrame = f
        if nowMs - lastVoiced > 600 { smooth = .nan }
        let ref = Prefs.shared.leadLevelDb
        relative = (smooth.isNaN || ref.isNaN) ? .nan : smooth - ref

        if !phrases.isEmpty {
            if loop {
                let ph = phrases[phraseIndex]
                if pos > Float(ph.endMs) + 500 {
                    seek(max(0, Float(ph.startMs) - 800))
                    return
                }
            } else {
                var p = phraseIndex
                while p < phrases.count - 1 && pos >= Float(phrases[p + 1].startMs) - 300 { p += 1 }
                while p > 0 && pos < Float(phrases[p].startMs) - 300 { p -= 1 }
                if p != phraseIndex { phraseIndex = p }
            }
        }
        if pos >= totalMs + 600 {
            pause()
            pausedAt = 0
            sliderPos = 0
            return
        }
        if nowMs - lastUi > 120 {
            lastUi = nowMs
            sliderPos = pos
            let a = scorer.frameAccuracy()
            let acc = a < 0 ? -1 : Int((a * 100).rounded())
            if acc != accuracy { accuracy = acc }
            if !(relativeText.isNaN && relative.isNaN) && relativeText != relative { relativeText = relative }
        }
    }

    /// Balance calibration: a few seconds of the melody sung at lead-voice volume.
    func calibrate() {
        guard !playing, !calibrating else { return }
        calibrationLevels = []
        calibration = 0
        calibrating = true
        hold.set(true)
        lastFrame = MicEngine.shared.frames
        startLink()
    }

    // MARK: note editing

    func setEditing(_ on: Bool) {
        if on && playing { pause() }
        editing = on
        selected = -1
        confirmPhraseDelete = false
        if !on { synth.stop() }
    }

    func pickNote(_ t: Float, _ m: Float) {
        var best = -1
        var bestScore = Float.greatestFiniteMagnitude
        for (i, n) in notes.enumerated() {
            let dt: Float = t < Float(n.startMs) ? Float(n.startMs) - t : (t > Float(n.endMs) ? t - Float(n.endMs) : 0)
            let score = dt / 150 + abs(Float(n.midi) - m)
            if score < bestScore {
                bestScore = score
                best = i
            }
        }
        selected = bestScore < 4 ? best : -1
        confirmPhraseDelete = false
        if selected >= 0 { synth.preview(notes[selected].midi) }
    }

    /// Index of the selected melody note inside the roll (the lead comes first in the roll).
    var selectedRollIndex: Int { editing && !config.backingMode ? selected : -1 }

    func editSelected(_ op: (NoteEvent) -> NoteEvent?) {
        let i = selected
        guard i >= 0 && i < notes.count else { return }
        if let changed = op(notes[i]) {
            notes[i] = changed
            synth.preview(changed.midi)
        } else {
            notes.remove(at: i)
            selected = -1
        }
        confirmPhraseDelete = false
        rebuild()
        persist()
    }

    /// Deletes every melody note of the phrase around the selected note (e.g. an instrumental fill).
    func deleteSelectedPhrase() {
        guard selected >= 0 && selected < notes.count else { return }
        let note = notes[selected]
        guard let phrase = Phrases.split(notes).first(where: { note.startMs >= $0.startMs && note.startMs < $0.endMs }) else { return }
        notes = notes.filter { $0.startMs < phrase.startMs || $0.startMs >= phrase.endMs }
        selected = -1
        confirmPhraseDelete = false
        rebuild()
        persist()
    }
}

struct PracticeScreen: View {
    let id: String
    var store = SongStore.shared

    var body: some View {
        Group {
            if let song = store.find(id) {
                MicGate { PracticeContent(song: song) }
            } else {
                Text(store.loaded ? "Música não encontrada." : "Carregando…").font(Typo.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, screenPadding)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private let practiceHelp = [
    "Ouça com \"Melodia\" ligada até conhecer bem a linha principal.",
    "Ponha a música em \"Sem voz\" e ouça só a \"2ª voz\" algumas vezes.",
    "Com fones, cante junto com a 2ª voz. A linha clara é você; as barras âmbar são o alvo.",
    "Volte a música para \"Original\" e cante com o guia da 2ª voz.",
    "Desligue o guia e cante só com a música. Mire em 80% ou mais.",
    "Use ◀ ▶ para andar de frase em frase, o botão de repetir para fixar um trecho e 0,75× para estudar devagar.",
]

private let backingHelp = [
    "Nos ajustes, escolha a voz do regente e o estilo de backing. O app escreve a sua parte na sua extensão.",
    "Ouça o arranjo com \"Regente\" e \"Sua parte\" ligados: o guia já toca no volume recomendado.",
    "Toque em \"calibrar\" e cante a melodia forte uma vez: essa é a referência do regente.",
    "Cante a sua parte com o guia, mantendo o ponto do medidor dentro da faixa âmbar.",
    "Desligue o guia e cante com a música em \"Sem voz\" (karaokê) ou \"Original\".",
]

private let edits: [(String, (NoteEvent) -> NoteEvent?)] = [
    ("8ª↓", { $0.with(midi: $0.midi - 12) }),
    ("−1", { $0.with(midi: $0.midi - 1) }),
    ("+1", { $0.with(midi: $0.midi + 1) }),
    ("8ª↑", { $0.with(midi: $0.midi + 12) }),
    ("Apagar", { _ in nil }),
]

private struct PracticeContent: View {
    let song: Song
    @Environment(Nav.self) var nav
    @State var model: PracticeModel?
    @State var showSettings = false
    @State var showHelp = false
    @State var confirmDelete = false
    @State var dragging: Float?
    var prefs = Prefs.shared
    var headphones = Headphones.shared

    var body: some View {
        VStack(spacing: 0) {
            if let model { content(model) }
        }
        .navigationTitle(song.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                IconButton(icon: "slider.horizontal.3", label: "Ajustes", tint: showSettings ? Palette.accent : Palette.text) { showSettings.toggle() }
                IconButton(icon: "trash", label: "Excluir") { confirmDelete = true }
            }
        }
        .confirmationDialog("Excluir \"\(song.title)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                model?.close()
                SongStore.shared.delete(song.id)
                nav.pop()
            }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear { if model == nil { model = PracticeModel(song: song) } }
        .onDisappear { model?.close() }
        .onChange(of: prefs.rangeLow) { _, _ in model?.rebuild() }
        .onChange(of: prefs.rangeHigh) { _, _ in model?.rebuild() }
    }

    @ViewBuilder
    private func content(_ model: PracticeModel) -> some View {
        let naming = prefs.naming
        let c = model.config
        Text(c.key.label(naming) + " · " + (c.backingMode ? c.style.label : c.mode.label))
            .font(Typo.small)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        ChoiceGrid(items: [false, true], columns: 2, selected: { $0 == c.backingMode }, label: { $0 ? "Backing vocal" : "Segunda voz" }, onSelect: { on in
            model.setEditing(false)
            model.change { $0.backingMode = on }
        })
        .padding(.bottom, 8)

        if showSettings {
            ScrollView { settings(model, naming).padding(.bottom, 8) }.frame(maxHeight: .infinity)
        } else {
            if c.backingMode && model.lines.mine.isEmpty {
                Text("Esta música não tem pausas entre as frases para respostas. Escolha outro estilo nos ajustes.")
                    .font(Typo.small)
                    .foregroundStyle(Palette.warn)
                    .padding(.bottom, 6)
            }
            PianoRoll(
                notes: model.roll,
                clock: { model.now() },
                trace: model.trace,
                naming: naming,
                flats: c.key.prefersFlats,
                windowMs: 6000,
                accuracy: { model.scorer.noteAccuracy($0) },
                selected: model.selectedRollIndex,
                emptyLabel: "trecho instrumental",
                running: true,
                onTap: model.editing ? { (t: Float, m: Float) in model.pickNote(t, m) } : nil,
                onScrub: model.playing ? nil : { (d: Float) in model.seek(model.now() + d) }
            )
            .frame(maxHeight: .infinity)
        }

        if model.editing { editor(model, naming) }

        if c.backingMode && !model.lines.mine.isEmpty { balance(model) }

        if model.playing && !headphones.connected { SpeakerWarning().padding(.top, 6) }
        transport(model)
        chips(model)
        help(model)
    }

    @ViewBuilder
    private func settings(_ model: PracticeModel, _ naming: Naming) -> some View {
        let c = model.config
        VStack(alignment: .leading, spacing: 6) {
            Caps("Tom da música")
            ChoiceGrid(items: Array(0..<12), columns: 6, selected: { $0 == c.key.tonic }, label: { NoteNames.pitchClass($0, naming, flats: Key($0, c.key.minor).prefersFlats) }, onSelect: { t in
                model.change { $0.key = Key(t, c.key.minor) }
            })
            ChoiceGrid(items: [false, true], columns: 2, selected: { $0 == c.key.minor }, label: { $0 ? "Menor" : "Maior" }, onSelect: { minor in
                model.change { $0.key = Key(c.key.tonic, minor) }
            })
            if !c.backingMode {
                Caps("Tipo de segunda voz").padding(.top, 12)
                ChoiceGrid(items: HarmonyMode.allCases, columns: 4, selected: { $0 == c.mode }, label: { $0.label }, onSelect: { m in
                    model.change { $0.mode = m }
                })
                HStack(alignment: .firstTextBaseline) {
                    Text(c.mode.summary).font(Typo.small).foregroundStyle(Palette.muted)
                    Spacer()
                    LinkText("aprender") { nav.push(.lesson(c.mode)) }
                }
                if c.mode.parallel {
                    StepperRow(
                        label: "Oitava da 2ª voz", value: c.octave > 0 ? "+\(c.octave)" : "\(c.octave)",
                        minus: { model.change { $0.octave = max(-2, $0.octave - 1) } },
                        plus: { model.change { $0.octave = min(2, $0.octave + 1) } }
                    )
                }
            } else {
                Caps("Voz do regente").padding(.top, 12)
                ChoiceGrid(items: VoiceType.allCases, columns: 3, selected: { $0 == c.leadVoice }, label: { $0.label }, onSelect: { v in
                    model.change { $0.leadVoice = v }
                })
                HStack(alignment: .firstTextBaseline) {
                    Text("Sua voz: \(prefs.voiceType.label) (\(NoteNames.full(prefs.rangeLow, naming))–\(NoteNames.full(prefs.rangeHigh, naming)))")
                        .font(Typo.small)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    LinkText("medir") { nav.push(.rangeTest) }
                }
                Caps("Estilo").padding(.top, 10)
                ChoiceGrid(items: BackingStyle.allCases, columns: 4, selected: { $0 == c.style }, label: { $0.label }, onSelect: { s in
                    model.change { $0.style = s }
                })
                Text(c.style.summary).font(Typo.small).foregroundStyle(Palette.muted)
                ChoiceGrid(items: [1, 2], columns: 2, selected: { $0 == c.voices }, label: { $0 == 1 ? "1 voz de backing" : "2 vozes de backing" }, onSelect: { n in
                    model.change {
                        $0.voices = n
                        if n == 1 { $0.part = 0 }
                    }
                })
                .padding(.top, 10)
                if let parts = model.lines.plan?.parts, parts.count == 2 {
                    ChoiceGrid(items: [0, 1], columns: 2, selected: { $0 == c.part }, label: { i in
                        let name = parts[i].name.components(separatedBy: " (").first ?? parts[i].name
                        return "Cantar: " + name + (i == 0 ? " agudo" : " grave")
                    }, onSelect: { p in model.change { $0.part = p } })
                }
            }
            PillButton("Corrigir notas da melodia", primary: false) {
                model.change { $0.backingMode = false }
                model.setEditing(true)
                showSettings = false
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func editor(_ model: PracticeModel, _ naming: Naming) -> some View {
        Panel {
            HStack {
                let n = model.selected >= 0 && model.selected < model.notes.count ? model.notes[model.selected] : nil
                Text(n.map { "\(NoteNames.full($0.midi, naming, flats: model.config.key.prefersFlats)) · \(formatTime(Float($0.startMs)))" } ?? "Toque numa nota da melodia")
                    .font(Typo.label)
                    .foregroundStyle(Palette.text)
                Spacer()
                LinkText("concluir") { model.setEditing(false) }
            }
            HStack(spacing: 8) {
                ForEach(0..<edits.count, id: \.self) { i in
                    Chip(text: edits[i].0, selected: false) { model.editSelected(edits[i].1) }
                }
            }
            .padding(.top, 8)
            if model.selected >= 0 {
                LinkText(
                    model.confirmPhraseDelete ? "Toque de novo para apagar a frase inteira" : "Apagar a frase toda (ex.: um solo instrumental)",
                    color: model.confirmPhraseDelete ? Palette.bad : Palette.accent
                ) {
                    if model.confirmPhraseDelete { model.deleteSelectedPhrase() } else { model.confirmPhraseDelete = true }
                }
                .padding(.top, 4)
            }
            Text("Arraste a faixa para os lados para andar pela música.").font(Typo.small).foregroundStyle(Palette.muted).padding(.top, 4)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func balance(_ model: PracticeModel) -> some View {
        let target = model.lines.mineDb
        let rel = model.relativeText
        let reference = prefs.leadLevelDb
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Caps("Equilíbrio")
                Spacer()
                Group {
                    if model.calibrating {
                        Text("cante a melodia forte… \(Int((min(model.calibration, 1) * 100).rounded()))%")
                    } else if reference.isNaN || rel.isNaN {
                        Text("alvo \(Int(target.rounded())) dB")
                    } else {
                        Text(String(format: "%+.0f dB · ", rel) + balanceHint(rel, target))
                    }
                }
                .font(Typo.small)
                .foregroundStyle(!rel.isNaN && abs(rel - target) <= 2.5 ? Palette.accent : Palette.muted)
                LinkText(reference.isNaN ? "calibrar" : "recalibrar") { model.calibrate() }
                    .disabled(model.playing || model.calibrating)
                    .padding(.leading, 6)
            }
            BalanceMeter(relative: { model.relative }, target: target, running: model.playing)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func transport(_ model: PracticeModel) -> some View {
        HStack {
            Text("\(formatTime(dragging ?? model.sliderPos)) / \(formatTime(model.totalMs))").font(Typo.small).foregroundStyle(Palette.muted)
            Spacer()
            statusText(model)
        }
        .padding(.top, 6)
        Slider(
            value: Binding(
                get: { Double(min(max(dragging ?? model.sliderPos, 0), max(1, model.totalMs))) },
                set: { dragging = Float($0) }
            ),
            in: 0...Double(max(1, model.totalMs)),
            onEditingChanged: { editing in
                if !editing, let d = dragging {
                    model.seek(d)
                    dragging = nil
                }
            }
        )
        .tint(Palette.text)
        HStack {
            IconButton(icon: "backward.end", label: "Do começo") { model.restart() }
            Spacer()
            IconButton(icon: "chevron.left", label: "Frase anterior") { model.goToPhrase(model.phraseIndex - 1) }
            Spacer()
            RoundButton(icon: model.playing ? "pause.fill" : "play.fill", label: model.playing ? "Pausar" : "Tocar", size: 64) { model.togglePlay() }
            Spacer()
            IconButton(icon: "chevron.right", label: "Próxima frase") { model.goToPhrase(model.phraseIndex + 1) }
            Spacer()
            IconButton(icon: "repeat", label: "Repetir frase", tint: model.loop ? Palette.accent : Palette.muted) { model.loop.toggle() }
        }
    }

    @ViewBuilder
    private func statusText(_ model: PracticeModel) -> some View {
        let acc = model.accuracy
        if model.playerState == 2 {
            Text("áudio indisponível").font(Typo.label).foregroundStyle(Palette.bad)
        } else if acc < 0 {
            Text(model.phrases.isEmpty ? "" : "frase \(model.phraseIndex + 1) de \(model.phrases.count)").font(Typo.label).foregroundStyle(Palette.muted)
        } else {
            Text((model.config.backingMode ? "backing" : "2ª voz") + " \(acc)%")
                .font(Typo.label)
                .foregroundStyle(acc >= 70 ? Palette.accent : (acc >= 40 ? Palette.warn : Palette.bad))
        }
    }

    @ViewBuilder
    private func chips(_ model: PracticeModel) -> some View {
        let backing = model.config.backingMode
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.player != nil {
                    Chip(text: model.music.map { "Música: \($0.label)" } ?? "Música desligada", selected: model.music != nil && model.playerState != 2) { model.nextMix() }
                }
                Chip(text: backing ? "Regente" : "Melodia", selected: model.leadOn) { model.toggleLead() }
                Chip(text: backing ? "Sua parte" : "2ª voz", selected: model.mineOn) { model.toggleMine() }
                if !model.lines.other.isEmpty {
                    Chip(text: "Outra voz", selected: model.otherOn) { model.toggleOther() }
                }
                Chip(text: model.speed == 1 ? "1×" : decimal(model.speed, digits: 2).replacingOccurrences(of: ",50", with: ",5") + "×", selected: model.speed != 1) { model.nextSpeed() }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func help(_ model: PracticeModel) -> some View {
        let backing = model.config.backingMode
        Panel(action: { showHelp.toggle() }) {
            HStack {
                Caps(backing ? "Como fazer o backing" : "Como praticar")
                Spacer()
                Text(showHelp ? "ocultar" : "mostrar").font(Typo.small).foregroundStyle(Palette.muted)
            }
            if showHelp {
                let steps = backing ? backingHelp : practiceHelp
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        Bullet(text: step, marker: "\(i + 1)")
                    }
                    let tips = model.lines.plan?.tips ?? []
                    if backing && !tips.isEmpty {
                        Caps("Para esta combinação de vozes").padding(.top, 8)
                        ForEach(tips, id: \.self) { Bullet(text: $0) }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 10)
    }
}
