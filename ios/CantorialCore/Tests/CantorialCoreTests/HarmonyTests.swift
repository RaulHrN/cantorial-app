import XCTest
import CantorialCore

final class HarmonyTests: XCTestCase {
    private let c = Key(0, false)

    private func intervals(_ melody: [NoteEvent], _ voice: [NoteEvent]) -> [Int] {
        zip(melody, voice).map { abs($0.1.midi - $0.0.midi) }
    }

    func testGuidedStaysInRangeAndMovesLittle() {
        let range = 52...64
        let v = Harmony.voice(ode, key: c, mode: .guided, range: range)
        XCTAssertEqual(v.count, ode.count)
        XCTAssertTrue(v.allSatisfy { range.contains($0.midi) })
        for iv in intervals(ode, v) { XCTAssertTrue([3, 4, 8, 9].contains(iv % 12), "interval \(iv)") }
        let maxLeap = zip(v, v.dropFirst()).map { abs($0.0.midi - $0.1.midi) }.max() ?? 0
        XCTAssertLessThanOrEqual(maxLeap, 4)
        XCTAssertTrue(v.allSatisfy { c.degreeOf($0.midi) >= 0 })
    }

    func testGuidedCanBeForcedAboveOrBelow() {
        let above = Harmony.guided(ode, key: c, range: 55...79, preferAbove: true)
        XCTAssertTrue(zip(ode, above).allSatisfy { $0.1.midi > $0.0.midi })
        let below = Harmony.guided(ode, key: c, range: 45...67, preferAbove: false)
        XCTAssertTrue(zip(ode, below).allSatisfy { $0.1.midi < $0.0.midi })
    }

    func testContraryMovesAgainstTheMelody() {
        let scale = line([60, 62, 64, 65, 67, 69, 71, 72])
        let v = Harmony.voice(scale, key: c, mode: .contrary, range: 48...72)
        for iv in intervals(scale, v) { XCTAssertTrue([3, 4, 7, 8, 9, 12, 15, 16].contains(iv), "interval \(iv)") }
        var contrary = 0
        for i in 1..<scale.count {
            let dm = scale[i].midi - scale[i - 1].midi
            let dv = v[i].midi - v[i - 1].midi
            if dv != 0 && (dv > 0) != (dm > 0) { contrary += 1 }
        }
        XCTAssertGreaterThanOrEqual(contrary, 4, "\(v.map(\.midi))")
        for i in 1..<scale.count {
            let a = abs(v[i - 1].midi - scale[i - 1].midi) % 12
            let b = abs(v[i].midi - scale[i].midi) % 12
            if v[i].midi != v[i - 1].midi { XCTAssertFalse(a == b && (a == 0 || a == 7)) }
        }
    }

    func testPedalHoldsOneNote() {
        let brilha = line([60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60])
        let v = Harmony.voice(brilha, key: c, mode: .pedal, range: 48...60)
        XCTAssertLessThanOrEqual(v.count, 6, "\(v.map(\.midi))")
        let longest = v.max { $0.durMs < $1.durMs }!
        XCTAssertEqual(floorMod(longest.midi, 12), 0)
        XCTAssertGreaterThanOrEqual(longest.durMs, 2000)
        for n in brilha {
            let h = v.first { n.startMs >= $0.startMs && n.startMs < $0.endMs }!
            XCTAssertFalse([1, 2, 6, 10, 11].contains(abs(n.midi - h.midi) % 12), "\(n.midi) over \(h.midi)")
        }
    }

    func testUnisonFitsTheRange() {
        let v = Harmony.voice(ode, key: c, mode: .unison, range: 72...86)
        XCTAssertEqual(v.map(\.midi), ode.map { $0.midi + 12 })
    }

    func testParallelTypesIgnoreTheRange() {
        let v = Harmony.voice(ode, key: c, mode: .thirdAbove, range: 30...40)
        XCTAssertEqual(v[0].midi, Harmony.note(64, key: c, steps: 2))
    }
}

final class BackingTests: XCTestCase {
    private let c = Key(0, false)

    func testRelationFollowsVoiceTypes() {
        XCTAssertEqual(Backing.relation(lead: .tenor, singer: VoiceType.bass.range), .lower)
        XCTAssertEqual(Backing.relation(lead: .baritone, singer: VoiceType.soprano.range), .higher)
        XCTAssertEqual(Backing.relation(lead: .tenor, singer: VoiceType.tenor.range), .same)
    }

    func testLeadIsPlacedInTheLeadRegister() {
        let plan = Backing.arrange(ode, key: c, style: .harmony, lead: .baritone, singer: VoiceType.tenor.range)
        let median = Harmony.median(plan.lead)
        XCTAssertTrue((VoiceType.baritone.low...VoiceType.baritone.high).contains(median))
        XCTAssertEqual(plan.leadShift % 12, 0)
    }

    func testLowerBackingSingsBelowAndSofter() {
        let plan = Backing.arrange(ode, key: c, style: .harmony, lead: .tenor, singer: VoiceType.baritone.range)
        XCTAssertEqual(plan.relation, .lower)
        XCTAssertEqual(plan.parts.count, 1)
        let part = plan.parts[0]
        XCTAssertTrue(zip(plan.lead, part.notes).allSatisfy { $0.1.midi < $0.0.midi })
        XCTAssertTrue(part.notes.allSatisfy { VoiceType.baritone.range.contains($0.midi) })
        XCTAssertTrue((-7 ... -4).contains(part.gainDb), "gain \(part.gainDb)")
        XCTAssertFalse(plan.tips.isEmpty)
    }

    func testFemaleBackingOverMaleLeadSingsAboveAndQuieter() {
        let plan = Backing.arrange(ode, key: c, style: .harmony, lead: .baritone, singer: VoiceType.mezzo.range)
        XCTAssertEqual(plan.relation, .higher)
        let part = plan.parts[0]
        XCTAssertTrue(zip(plan.lead, part.notes).allSatisfy { $0.1.midi > $0.0.midi })
        XCTAssertTrue(part.notes.allSatisfy { VoiceType.mezzo.range.contains($0.midi) })
        XCTAssertLessThanOrEqual(part.gainDb, -8)
        XCTAssertTrue(plan.tips.contains { $0.contains("oitava") })
    }

    func testTrioFormsTriads() {
        let plan = Backing.arrange(ode, key: c, style: .harmony, lead: .tenor, singer: VoiceType.tenor.range, voices: 2)
        XCTAssertEqual(plan.parts.count, 2)
        let hi = plan.parts[0]
        let lo = plan.parts[1]
        for i in plan.lead.indices {
            let pcs = Set([plan.lead[i].midi, hi.notes[i].midi, lo.notes[i].midi].map { floorMod($0, 12) })
            XCTAssertEqual(pcs.count, 3, "chord at \(i): \(pcs)")
            let ok = (0..<6).contains { r in
                Set([r, (r + 2) % 7, (r + 4) % 7].map { Key.majorScale[$0] }).isSuperset(of: pcs)
            }
            XCTAssertTrue(ok, "not a triad: \(pcs)")
            XCTAssertGreaterThan(hi.notes[i].midi, lo.notes[i].midi)
        }
        XCTAssertLessThan(plan.parts[0].gainDb, plan.parts[1].gainDb)
    }

    func testPadHoldsChordTones() {
        let plan = Backing.arrange(ode, key: c, style: .pad, lead: .tenor, singer: VoiceType.baritone.range)
        let pad = plan.parts[0].notes
        XCTAssertTrue((3...(ode.count / 2)).contains(pad.count), "pad has \(pad.count) notes")
        XCTAssertTrue(pad.allSatisfy { c.degreeOf($0.midi) >= 0 })
        XCTAssertTrue(pad.allSatisfy { VoiceType.baritone.range.contains($0.midi) })
        XCTAssertLessThanOrEqual(plan.parts[0].gainDb, -9)
        for n in plan.lead {
            guard let p = pad.first(where: { n.startMs >= $0.startMs && n.startMs < $0.endMs + 100 }) else { continue }
            XCTAssertFalse([1, 6, 11].contains(abs(n.midi - p.midi) % 12), "\(n.midi) over \(p.midi)")
        }
    }

    func testEchoAnswersInTheGaps() {
        let phrase1 = line([60, 62, 64, 60])
        let phrase2 = line([64, 65, 67]).map { NoteEvent($0.startMs + 3500, $0.durMs, $0.midi) }
        let plan = Backing.arrange(phrase1 + phrase2, key: c, style: .echo, lead: .tenor, singer: VoiceType.tenor.range)
        let echo = plan.parts[0].notes
        XCTAssertFalse(echo.isEmpty)
        for e in echo {
            for l in plan.lead { XCTAssertTrue(e.endMs <= l.startMs || e.startMs >= l.endMs) }
        }
        let first = echo.filter { $0.startMs < 3500 }.map { floorMod($0.midi, 12) }
        XCTAssertEqual(first, Array([0, 2, 4, 0].suffix(first.count)))
    }

    func testDoubleIsUnisonOrOctave() {
        let plan = Backing.arrange(ode, key: c, style: .double, lead: .tenor, singer: VoiceType.soprano.range)
        let d = plan.parts[0].notes
        XCTAssertTrue(zip(plan.lead, d).allSatisfy { ($0.1.midi - $0.0.midi) % 12 == 0 })
        XCTAssertTrue(d.allSatisfy { (VoiceType.soprano.low...VoiceType.soprano.high).contains($0.midi) })
    }
}

final class ContentTests: XCTestCase {
    func testContentIsBundled() {
        XCTAssertGreaterThanOrEqual(Content.exercises.count, 20)
        XCTAssertFalse(Content.studies.isEmpty)
        XCTAssertFalse(Content.tips.isEmpty)
        XCTAssertFalse(Content.tipOfTheDay().isEmpty)
        XCTAssertEqual(Content.lessonExample.pattern.count, Content.lessonExample.beats.count)
    }

    func testEveryHarmonyTypeHasALessonWithAnExercise() {
        for mode in HarmonyMode.allCases {
            let lesson = Content.lesson(mode)
            XCTAssertNotNil(lesson, "no lesson for \(mode)")
            if let lesson { XCTAssertNotNil(Content.exercise(lesson.exerciseId), "missing \(lesson.exerciseId)") }
        }
    }

    func testExerciseTimelinesForBackingAndHarmonyTypes() {
        let range = 48...67
        for id in ["backing-pad", "backing-resposta", "backing-dobra", "backing-trio", "segunda-conduzida", "segunda-pedal", "segunda-contraria"] {
            let ex = Content.exercise(id)!
            let roots = ExercisePlan.roots(ex, low: range.lowerBound, high: range.upperBound, seed: 1)
            let tl = ExerciseTimeline.build(ex, root: roots[0], range: range)
            XCTAssertFalse(tl.targets.isEmpty, "\(id) has no targets")
            XCTAssertTrue(tl.targets.allSatisfy { $0.startMs >= tl.singStartMs }, id)
            XCTAssertTrue(zip(tl.targets, tl.targets.dropFirst()).allSatisfy { $0.0.startMs <= $0.1.startMs }, id)
            XCTAssertGreaterThan(tl.lengthMs, tl.targets.last!.endMs, id)
        }
        let trio = ExerciseTimeline.build(Content.exercise("backing-trio")!, root: 55, range: range)
        XCTAssertTrue(trio.notes.contains { $0.role == .accomp && $0.gain < 1 })
    }

    func testEveryExerciseBuildsATimeline() {
        // Breathing and balance exercises have no notes to play or sing.
        for ex in Content.exercises where ex.kind != .breath && ex.kind != .balance {
            let tl = ExerciseTimeline.build(ex, root: 57, range: 45...69)
            XCTAssertGreaterThan(tl.lengthMs, 0, ex.id)
        }
    }
}
