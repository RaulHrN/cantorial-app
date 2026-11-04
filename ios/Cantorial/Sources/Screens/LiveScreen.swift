import CantorialCore
import SwiftUI

/// Follows the microphone: the current note, how in tune it is and a list of recent notes.
@Observable
final class LiveModel {
    private(set) var note = -1
    private(set) var info = ""
    private(set) var recent: [Int] = []
    private(set) var error: String?
    @ObservationIgnored private(set) var cents: Float = 0
    private let follower = NoteFollower(historySize: 8)
    private let hold = MicHold()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var lastFrame: Int64 = 0
    @ObservationIgnored private var lastNote = -1
    @ObservationIgnored private var lastInfo: Double = 0
    @ObservationIgnored private var version = -1

    func start() {
        hold.set(true)
        lastFrame = MicEngine.shared.frames
        let l = DisplayLink { [weak self] _ in self?.frame() }
        link = l
        l.start()
    }

    func stop() {
        link?.stop()
        link = nil
        hold.set(false)
    }

    func clear() { follower.clear() }

    private func frame() {
        let mic = MicEngine.shared
        let f = mic.frames
        var i = max(lastFrame, f - 32)
        while i < f {
            let idx = mic.index(i)
            follower.update(mic.midi[idx], nowMs: Double(mic.timeNs[idx]) / 1e6)
            i += 1
        }
        lastFrame = f
        // Smooth the meter (~120 ms) so a natural vibrato does not make it jump around.
        if follower.note != lastNote {
            lastNote = follower.note
            cents = follower.cents
        } else {
            cents += (follower.cents - cents) * 0.12
        }
        if note != follower.note { note = follower.note }
        if version != follower.version {
            version = follower.version
            recent = Array(follower.recentNotes.suffix(6))
        }
        if error != mic.error { error = mic.error }
        let now = HostClock.nowMs()
        if now - lastInfo > 120 {
            lastInfo = now
            var text = ""
            if follower.note >= 0 {
                let hz = Pitch.midiToHz(Float(follower.note) + cents / 100, a4: Prefs.shared.a4)
                let c = Int(cents.rounded())
                let tuning = abs(c) <= 5 ? "afinado" : (c > 0 ? "+\(c)" : "\(c)") + " cents"
                text = decimal(hz) + " Hz  ·  " + tuning
            }
            if text != info { info = text }
        }
    }
}

struct LiveScreen: View {
    @Environment(Nav.self) var nav
    var prefs = Prefs.shared

    var body: some View {
        MicGate { LiveContent(naming: prefs.naming) }
            .padding(.horizontal, screenPadding)
            .navigationTitle("Ouvir")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(icon: "slider.horizontal.3", label: "Ajustes") { nav.push(.settings) }
                }
            }
    }
}

private struct LiveContent: View {
    let naming: Naming
    @State var model = LiveModel()

    var body: some View {
        VStack(spacing: 0) {
            NoteReadout(note: model.note, naming: naming).padding(.top, 8)
            Text(model.error ?? (model.note < 0 ? "Cante, fale ou toque uma nota" : model.info))
                .font(Typo.small)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
            CentsMeter(cents: { model.cents }, active: { model.note >= 0 }).padding(.top, 12)
            LiveTrace(naming: naming).frame(maxHeight: .infinity).padding(.vertical, 12)
            HStack {
                Caps("Recentes", color: Palette.faint)
                Spacer()
                if !model.recent.isEmpty {
                    LinkText("limpar", color: Palette.muted) { model.clear() }
                }
            }
            HStack(spacing: 14) {
                ForEach(Array(model.recent.enumerated()), id: \.offset) { k, n in
                    Text(NoteNames.full(n, naming))
                        .font(Typo.label)
                        .foregroundStyle(k == model.recent.count - 1 ? Palette.text : Palette.muted)
                }
                Spacer()
            }
            .frame(height: 28)
            LevelBar(level: { MicEngine.shared.latestLevel() }).padding(.vertical, 12)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
