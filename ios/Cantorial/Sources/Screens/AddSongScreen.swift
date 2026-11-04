import CantorialCore
import SwiftUI
import UniformTypeIdentifiers

enum SongSource: CaseIterable {
    case file, sing, type

    var label: String {
        switch self {
        case .file: return "Do arquivo"
        case .sing: return "Cantando"
        case .type: return "Digitando"
        }
    }
}

struct AddSongScreen: View {
    @Environment(Nav.self) var nav
    var prefs = Prefs.shared
    @State var title = ""
    @State var audioFile: String?
    @State var audioName: String?
    @State var source: SongSource = .file
    @State var notes: [NoteEvent]?
    @State var durationMs = 0
    @State var voiced: Float?
    @State var error: String?
    @State var progress: Float = -1
    @State var job: Task<Void, Never>?
    @State var picking = false
    @State var saved = false

    var body: some View {
        let naming = prefs.naming
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Nome da música", text: $title)
                        .font(Typo.body)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    SectionTitle("Áudio (opcional)")
                    Panel(action: { picking = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus").font(.system(size: 20)).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audioName ?? "Escolher arquivo").font(Typo.body).foregroundStyle(Palette.text).lineLimit(1)
                                Text(audioName == nil ? "MP3, M4A, WAV, AIFF… para tocar junto e extrair a melodia" : "Toque para trocar")
                                    .font(Typo.small)
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    SectionTitle("Melodia")
                    HStack(spacing: 8) {
                        ForEach(SongSource.allCases, id: \.self) { s in
                            Chip(text: s.label, selected: source == s) {
                                if source != s {
                                    job?.cancel()
                                    source = s
                                    notes = nil
                                    error = nil
                                }
                            }
                        }
                    }
                    .padding(.bottom, 14)
                    switch source {
                    case .file: fileSource
                    case .sing:
                        SingSource(audioURL: audioFile.map { SongStore.audioFolder.appendingPathComponent($0) }) { n, d in
                            if n.count < 2 {
                                error = "Não ouvi notas suficientes. Cante mais perto do iPhone."
                                notes = nil
                            } else {
                                error = nil
                                notes = n
                                durationMs = d
                            }
                        }
                    case .type:
                        TypeSource { n, e in
                            notes = n
                            error = e
                            durationMs = 0
                        }
                    }
                    if let n = notes, let last = n.last {
                        let key = KeyDetector.detect(n)
                        Panel {
                            Caps("Melodia encontrada", color: Palette.accent)
                            Text("\(n.count) notas · \(key.label(naming)) · \(formatTime(Float(max(durationMs, last.endMs))))")
                                .font(Typo.body)
                                .foregroundStyle(Palette.text)
                                .padding(.top, 6)
                            if let v = voiced, source == .file {
                                Text("Voz encontrada em \(Int((v * 100).rounded()))% da música; o resto é instrumental.").font(Typo.small).foregroundStyle(Palette.muted)
                            }
                            Text("Na próxima tela você escolhe o tipo de segunda voz ou o backing vocal.").font(Typo.small).foregroundStyle(Palette.muted)
                        }
                        .padding(.top, 16)
                    }
                    if let error {
                        Text(error).font(Typo.small).foregroundStyle(Palette.bad).padding(.top, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            PillButton("Salvar e praticar", enabled: !(notes ?? []).isEmpty && progress < 0) { save() }
                .padding(.vertical, 12)
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle("Nova música")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            do {
                let name = try SongStore.importAudio(url)
                discardAudio()
                audioFile = name
                audioName = url.lastPathComponent
                if title.trimmingCharacters(in: .whitespaces).isEmpty { title = url.deletingPathExtension().lastPathComponent }
                if source == .file { notes = nil }
                error = nil
            } catch {
                self.error = "Não consegui abrir este arquivo."
            }
        }
        .onDisappear {
            job?.cancel()
            if !saved { discardAudio() }
        }
    }

    @ViewBuilder
    private var fileSource: some View {
        Text("O app separa a voz do instrumental (pela posição no estéreo, pelos harmônicos, pelo vibrato e pela forma como cada nota soa) e transcreve só o que é cantado. Se alguma nota sair errada, corrija na prática ou use \"Cantando\".")
            .font(Typo.small)
            .foregroundStyle(Palette.muted)
            .padding(.bottom, 12)
        if audioFile == nil {
            Text("Escolha um arquivo de áudio acima.").font(Typo.label).foregroundStyle(Palette.text)
        } else if progress >= 0 {
            ProgressLine(value: progress)
            HStack {
                Text("Analisando… \(Int((progress * 100).rounded()))%").font(Typo.small).foregroundStyle(Palette.muted)
                Spacer()
                LinkText("cancelar", color: Palette.muted) { job?.cancel() }
            }
            .padding(.top, 8)
        } else if notes == nil {
            PillButton("Encontrar a melodia") { analyze() }
        }
    }

    private func analyze() {
        guard let file = audioFile else { return }
        let url = SongStore.audioFolder.appendingPathComponent(file)
        error = nil
        progress = 0
        job = Task { @MainActor in
            defer { progress = -1 }
            do {
                let r = try await FileAnalyzer.analyze(url) { p in
                    Task { @MainActor in if progress >= 0 { progress = p } }
                }
                if r.notes.count < 4 {
                    error = "Não encontrei voz cantada neste arquivo. Se for instrumental, use \"Cantando\" ou \"Digitando\"."
                } else {
                    notes = r.notes
                    durationMs = r.durationMs
                    voiced = r.voicedRatio
                }
            } catch is CancellationError {
            } catch {
                self.error = "Não consegui ler este arquivo."
            }
        }
    }

    private func discardAudio() {
        if let f = audioFile {
            try? FileManager.default.removeItem(at: SongStore.audioFolder.appendingPathComponent(f))
        }
        audioFile = nil
        audioName = nil
    }

    private func save() {
        guard let n = notes, let last = n.last else { return }
        let key = KeyDetector.detect(n)
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let song = Song(
            id: UUID().uuidString,
            title: trimmed.isEmpty ? "Sem título" : trimmed,
            audioFile: audioFile,
            notes: n,
            key: key,
            mode: .thirdAbove,
            octave: bestOctave(n, key),
            createdAt: Date(),
            durationMs: max(durationMs, last.endMs)
        )
        saved = true
        SongStore.shared.upsert(song)
        nav.replace(.practice(song.id))
    }

    /// Octave shift that brings the default second voice closest to the user's vocal range.
    private func bestOctave(_ notes: [NoteEvent], _ key: Key) -> Int {
        let voice = Harmony.voice(notes, key: key, mode: .thirdAbove).map(\.midi).sorted()
        if voice.isEmpty { return 0 }
        let median = voice[voice.count / 2]
        let center = (prefs.rangeLow + prefs.rangeHigh) / 2
        return min(max(Int((Float(center - median) / 12).rounded()), -2), 2)
    }
}

/// Records the user singing the melody, optionally over the song.
@Observable
final class SingModel {
    private(set) var recording = false
    private(set) var elapsed: Float = 0
    private(set) var current = -1
    var withMusic: Bool
    let player: StemPlayer?
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var track: [Float] = []
    @ObservationIgnored private var levels: [Float] = []
    @ObservationIgnored private var follower = NoteFollower()
    @ObservationIgnored private var startNs: Int64 = 0
    @ObservationIgnored private var firstMs: Float = .nan
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var useMusic = false
    @ObservationIgnored private var lastUi: Double = 0
    @ObservationIgnored var onResult: (([NoteEvent], Int) -> Void)?

    init(audioURL: URL?) {
        player = audioURL.map { StemPlayer(url: $0) }
        withMusic = audioURL != nil
        player?.prepare {}
    }

    func toggle() {
        recording ? finish() : begin()
    }

    private func begin() {
        hold.set(true)
        track = []
        levels = []
        follower = NoteFollower()
        firstMs = .nan
        useMusic = withMusic && player?.ready == true
        if useMusic { player?.play(fromMs: 0, speed: 1) }
        startNs = HostClock.nowNs()
        lastFrame = MicEngine.shared.frames
        recording = true
        let l = DisplayLink { [weak self] _ in self?.frame() }
        link = l
        l.start()
    }

    func finish() {
        guard recording else { return }
        link?.stop()
        link = nil
        hold.set(false)
        player?.pause()
        recording = false
        let mic = MicEngine.shared
        let notes = track.count < 10 ? [] : Segmenter.segment(
            track, hopMs: mic.hopMs, firstFrameMs: max(0, firstMs.isNaN ? 0 : firstMs),
            onsets: Segmenter.onsets(levels, minDb: -55)
        )
        let duration = useMusic ? (player?.durationMs ?? 0) : (notes.last?.endMs ?? 0)
        onResult?(notes, duration)
    }

    private func frame() {
        let mic = MicEngine.shared
        let f = mic.frames
        let nowNs = HostClock.nowNs()
        let clock = useMusic ? (player?.positionMs() ?? 0) : Float(nowNs - startNs) / 1e6
        var i = max(lastFrame, f - 64)
        while i < f {
            let idx = mic.index(i)
            if mic.timeNs[idx] >= startNs {
                if firstMs.isNaN { firstMs = clock - Float(nowNs - mic.timeNs[idx]) / 1e6 - mic.latencyMs }
                track.append(mic.midi[idx])
                levels.append(mic.levelDb[idx])
                follower.update(mic.midi[idx], nowMs: Double(mic.timeNs[idx]) / 1e6)
            }
            i += 1
        }
        lastFrame = f
        if current != follower.note { current = follower.note }
        let now = HostClock.nowMs()
        if now - lastUi > 250 {
            lastUi = now
            elapsed = clock
        }
    }
}

private struct SingSource: View {
    let audioURL: URL?
    let onResult: ([NoteEvent], Int) -> Void
    @State var model: SingModel?
    var prefs = Prefs.shared

    var body: some View {
        MicGate {
            if let model { content(model) }
        }
        .frame(height: 340)
        .onAppear {
            if model == nil {
                let m = SingModel(audioURL: audioURL)
                m.onResult = onResult
                model = m
            }
        }
        .onDisappear { model?.finish() }
    }

    @ViewBuilder
    private func content(_ model: SingModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if audioURL != nil {
                ToggleRow(
                    label: "Tocar a música enquanto canto",
                    isOn: Binding(get: { model.withMusic }, set: { if !model.recording { model.withMusic = $0 } }),
                    detail: "Use fones para o microfone ouvir só você"
                )
            }
            Text(model.recording ? "Cante a melodia principal, sem pressa." : "Toque no microfone e cante a melodia que quer harmonizar.")
                .font(Typo.small)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                RoundButton(icon: model.recording ? "stop.fill" : "mic.fill", label: model.recording ? "Parar" : "Gravar", size: 64) { model.toggle() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.recording ? "Gravando" : "Pronto").font(Typo.label).foregroundStyle(model.recording ? Palette.accent : Palette.text)
                    Text(formatTime(model.elapsed)).font(Typo.small).foregroundStyle(Palette.muted)
                }
                Spacer()
                NoteReadout(note: model.current, naming: prefs.naming, large: false)
            }
            LiveTrace(naming: prefs.naming, running: model.recording).frame(height: 140)
        }
    }
}

private struct TypeSource: View {
    let onResult: ([NoteEvent]?, String?) -> Void
    @State var text = ""
    @State var bpm = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(Typo.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Separe as notas por espaço: Dó Ré Mi Fá# Sol (ou C D E F# G).\n\":2\" = dura 2 tempos · \"-\" = pausa · número = oitava (Dó4 é o Dó central).")
                .font(Typo.small)
                .foregroundStyle(Palette.muted)
            LinkText("Inserir exemplo") { text = "Dó4 Dó Sol Sol Lá Lá Sol:2 Fá Fá Mi Mi Ré Ré Dó:2" }
            StepperRow(label: "Andamento", value: "\(bpm) bpm", minus: { bpm = max(40, bpm - 4) }, plus: { bpm = min(220, bpm + 4) })
        }
        .onChange(of: text) { _, _ in parse() }
        .onChange(of: bpm) { _, _ in parse() }
    }

    private func parse() {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onResult(nil, nil)
        } else {
            let r = Notation.parse(text, bpm: bpm)
            onResult(r.error == nil ? r.notes : nil, r.error)
        }
    }
}
