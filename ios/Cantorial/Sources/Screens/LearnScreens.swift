import CantorialCore
import SwiftUI

/// The example phrase ("Ode à Alegria") placed comfortably in the singer's range.
private func exampleMelody(_ range: ClosedRange<Int>) -> ([NoteEvent], Key) {
    let root = (range.lowerBound + range.upperBound) / 2 - 4
    let example = Content.lessonExample
    let ex = Exercise(id: "exemplo", pattern: example.pattern.map { Optional($0) }, beats: example.beats, bpm: 96)
    return (ExerciseTimeline.melody(ex, root: root), Key(floorMod(root, 12), false))
}

/// Plays a short example and moves the roll along with it.
@Observable
final class ExampleModel {
    private(set) var playing = false
    let synth = Synth()
    @ObservationIgnored private var link: DisplayLink?
    @ObservationIgnored private var lengthMs: Float = 0

    func play(_ tracks: [SynthTrack], lengthMs: Int) {
        synth.a4 = Prefs.shared.a4
        synth.start(tracks, from: 0)
        self.lengthMs = Float(lengthMs)
        playing = true
        if link == nil {
            let l = DisplayLink { [weak self] _ in
                guard let self else { return }
                if self.synth.positionMs() > self.lengthMs + 300 { self.stop() }
            }
            link = l
            l.start()
        }
    }

    func stop() {
        synth.stop()
        link?.stop()
        link = nil
        playing = false
    }

    func clock() -> Float { playing ? synth.positionMs() : 0 }
}

private struct ExampleRoll: View {
    let notes: [RollNote]
    let lengthMs: Int
    let model: ExampleModel
    var prefs = Prefs.shared

    var body: some View {
        PianoRoll(
            notes: notes,
            clock: { model.clock() },
            naming: prefs.naming,
            windowMs: Float(lengthMs + 1200),
            playhead: 0.04,
            running: model.playing
        )
        .frame(height: 220)
    }
}

private struct Legend: View {
    let items: [(Color, String)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<items.count, id: \.self) { i in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(items[i].0).frame(width: 14, height: 6)
                    Text(items[i].1).font(Typo.small).foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

private struct LevelDots: View {
    let level: Int

    var body: some View {
        VStack(spacing: 3) {
            ForEach([3, 2, 1], id: \.self) { i in
                Circle().fill(i <= level ? Palette.accent : Palette.line).frame(width: 6, height: 6)
            }
        }
    }
}

struct LessonsScreen: View {
    @Environment(Nav.self) var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cada tipo tem um som e uma função. Comece pelos de nível 1 e avance quando a afinação estiver firme.")
                    .font(Typo.small)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 8)
                ForEach(HarmonyMode.allCases) { mode in
                    HStack(spacing: 12) {
                        LevelDots(level: mode.level)
                        ListRow(title: mode.label, subtitle: mode.summary) { nav.push(.lesson(mode)) }
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .navigationTitle("Tipos de segunda voz")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LessonScreen: View {
    let mode: HarmonyMode
    @Environment(Nav.self) var nav
    @State var player = ExampleModel()
    var prefs = Prefs.shared

    var body: some View {
        let lesson = Content.lesson(mode)
        let (melody, key) = exampleMelody(prefs.range)
        let voice = Harmony.voice(melody, key: key, mode: mode, range: prefs.range)
        let length = max(melody.last?.endMs ?? 0, voice.last?.endMs ?? 0)
        let notes = melody.map { RollNote(startMs: $0.startMs, durMs: $0.durMs, midi: $0.midi, kind: .melody) }
            + voice.enumerated().map { RollNote(startMs: $0.element.startMs, durMs: $0.element.durMs, midi: $0.element.midi, kind: .target, target: $0.offset) }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Segunda voz · nível \(mode.level)").font(Typo.small).foregroundStyle(Palette.muted).padding(.bottom, 8)
                    if let lesson {
                        Text(lesson.whenToUse).font(Typo.body).foregroundStyle(Palette.text)
                        SectionTitle("Como pensar")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(lesson.howTo, id: \.self) { Bullet(text: $0, font: Typo.body) }
                        }
                    }
                    SectionTitle("Exemplo: \"Ode à Alegria\"")
                    Legend(items: [(Palette.melody, "melodia"), (Palette.accent, "segunda voz")]).padding(.bottom, 6)
                    ExampleRoll(notes: notes, lengthMs: length, model: player)
                    HStack(spacing: 8) {
                        PillButton(player.playing ? "Parar" : "Ouvir os dois", icon: player.playing ? "stop.fill" : "play.fill", primary: false) {
                            if player.playing {
                                player.stop()
                            } else {
                                player.play([SynthTrack(melody, gain: 0.26), SynthTrack(voice, gain: 0.24, bright: true)], lengthMs: length)
                            }
                        }
                        PillButton("Só a 2ª voz", primary: false) {
                            player.play([SynthTrack(voice, gain: 0.26, bright: true)], lengthMs: length)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.bottom, 16)
            }
            if let lesson {
                PillButton("Praticar este tipo", icon: "mic") { nav.push(.exercise(lesson.exerciseId, nil)) }
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle(mode.label)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

private func backingExercise(_ style: BackingStyle, _ voices: Int) -> String {
    switch style {
    case .harmony: return voices == 2 ? "backing-trio" : "backing-harmonia"
    case .pad: return "backing-pad"
    case .echo: return "backing-resposta"
    case .double: return "backing-dobra"
    }
}

/// One voice of the arrangement with its loudness relative to the lead (0 dB).
private struct BalanceRow: View {
    let name: String
    let place: String
    let db: Float
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Typo.label).foregroundStyle(Palette.text)
                    if !place.isEmpty { Text(place).font(Typo.small).foregroundStyle(Palette.muted) }
                }
                Spacer()
                Text(db == 0 ? "0 dB" : "\(Int(db.rounded())) dB").font(Typo.label).foregroundStyle(Palette.text)
            }
            // Bar length follows perceived loudness: about half for every 10 dB.
            let share = CGFloat(min(max(pow(2, Double(db) / 10), 0.05), 1))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2)
                    Capsule().fill(color).frame(width: g.size.width * share)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Backing vocal lab: pick the lead singer's voice type and a style; see where your part goes,
/// how loud each voice should be, and listen to the balanced arrangement.
struct BackingLabScreen: View {
    @Environment(Nav.self) var nav
    @State var lead: VoiceType?
    @State var style: BackingStyle = .harmony
    @State var voices = 1
    @State var part = 0
    @State var player = ExampleModel()
    var prefs = Prefs.shared

    var body: some View {
        let naming = prefs.naming
        let singer = prefs.range
        let singerType = prefs.voiceType
        let leadVoice = lead ?? singerType
        let plan = arrangement(leadVoice, singer)
        let mineIndex = plan.parts.isEmpty ? -1 : min(max(part, 0), plan.parts.count - 1)
        let notes = rollNotes(plan, mineIndex)
        let length = (plan.lead + plan.parts.flatMap(\.notes)).map(\.endMs).max() ?? 0
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        Caps("Voz do regente")
                        ChoiceGrid(items: VoiceType.allCases, columns: 3, selected: { $0 == leadVoice }, label: { $0.label }, onSelect: { lead = $0 })
                        HStack(alignment: .firstTextBaseline) {
                            Text("Sua voz: \(singerType.label) (\(NoteNames.full(singer.lowerBound, naming))–\(NoteNames.full(singer.upperBound, naming)))")
                                .font(Typo.small)
                                .foregroundStyle(Palette.muted)
                            Spacer()
                            LinkText("medir") { nav.push(.rangeTest) }
                        }
                        Caps("Estilo").padding(.top, 10)
                        ChoiceGrid(items: BackingStyle.allCases, columns: 4, selected: { $0 == style }, label: { $0.label }, onSelect: { style = $0 })
                        Text(style.summary).font(Typo.small).foregroundStyle(Palette.muted)
                        ChoiceGrid(items: [1, 2], columns: 2, selected: { $0 == voices }, label: { $0 == 1 ? "1 voz de backing" : "2 vozes de backing" }, onSelect: {
                            voices = $0
                            if $0 == 1 { part = 0 }
                        })
                        .padding(.top, 10)
                        if plan.parts.count == 2 {
                            ChoiceGrid(items: [0, 1], columns: 2, selected: { $0 == part }, label: { $0 == 0 ? "Cantar a aguda" : "Cantar a grave" }, onSelect: { part = $0 })
                        }
                    }
                    Group {
                        SectionTitle("Equilíbrio")
                        Panel {
                            VStack(spacing: 10) {
                                BalanceRow(name: "Regente (\(leadVoice.label))", place: "melodia", db: 0, color: Palette.melody)
                                ForEach(Array(plan.parts.enumerated()), id: \.offset) { i, p in
                                    BalanceRow(name: i == mineIndex ? "\(p.name) · você" : p.name, place: p.place, db: p.gainDb, color: i == mineIndex ? Palette.accent : Palette.rose)
                                }
                            }
                        }

                        SectionTitle("Exemplo: \"Ode à Alegria\"")
                        Legend(items: [(Palette.melody, "regente"), (Palette.accent, "sua parte"), (Palette.rose, "outra voz")]).padding(.bottom, 6)
                        ExampleRoll(notes: notes, lengthMs: length, model: player)
                        HStack(spacing: 8) {
                            PillButton(player.playing ? "Parar" : "Ouvir equilibrado", icon: player.playing ? "stop.fill" : "play.fill", primary: false) {
                                if player.playing {
                                    player.stop()
                                } else {
                                    var tracks = [SynthTrack(plan.lead, gain: 0.3)]
                                    for (i, p) in plan.parts.enumerated() {
                                        tracks.append(SynthTrack(p.notes, gain: 0.3 * dbToGain(p.gainDb) * 1.4, bright: i == mineIndex))
                                    }
                                    player.play(tracks, lengthMs: length)
                                }
                            }
                            PillButton("Só a sua parte", primary: false, enabled: mineIndex >= 0) {
                                if mineIndex >= 0 { player.play([SynthTrack(plan.parts[mineIndex].notes, gain: 0.28, bright: true)], lengthMs: length) }
                            }
                        }
                        .padding(.top, 10)

                        SectionTitle("Dicas para esta combinação")
                        ForEach(plan.tips, id: \.self) { Bullet(text: $0).padding(.vertical, 2) }
                    }
                }
                .padding(.bottom, 16)
            }
            PillButton("Praticar", icon: "mic") { nav.push(.exercise(backingExercise(style, voices), leadVoice)) }
                .padding(.vertical, 12)
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle("Backing vocal")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private func arrangement(_ leadVoice: VoiceType, _ singer: ClosedRange<Int>) -> BackingPlan {
        let (melody, key) = exampleMelody(singer)
        // Echoes need rests: split the example into two phrases.
        let line = style == .echo ? melody.map { $0.startMs >= 4000 ? NoteEvent($0.startMs + 1800, $0.durMs, $0.midi) : $0 } : melody
        return Backing.arrange(line, key: key, style: style, lead: leadVoice, singer: singer, voices: voices)
    }

    private func rollNotes(_ plan: BackingPlan, _ mine: Int) -> [RollNote] {
        var out = plan.lead.map { RollNote(startMs: $0.startMs, durMs: $0.durMs, midi: $0.midi, kind: .melody) }
        for (i, p) in plan.parts.enumerated() where i != mine {
            out += p.notes.map { RollNote(startMs: $0.startMs, durMs: $0.durMs, midi: $0.midi, kind: .part) }
        }
        if mine >= 0 {
            out += plan.parts[mine].notes.enumerated().map {
                RollNote(startMs: $0.element.startMs, durMs: $0.element.durMs, midi: $0.element.midi, kind: .target, target: $0.offset)
            }
        }
        return out
    }
}
