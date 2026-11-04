import Foundation

/// A study text. The body uses a tiny markup: "# " starts a heading, "- " a bullet.
public struct Article: Codable, Identifiable, Hashable {
    public let title: String
    public let summary: String
    public let body: String
    public var id: String { title }
}

/// How to sing one type of second voice.
public struct Lesson: Codable, Identifiable {
    public let mode: HarmonyMode
    public let whenToUse: String
    public let howTo: [String]
    public let exerciseId: String
    public var id: String { mode.rawValue }
}

/// The melody every lesson harmonises (scale degrees as semitones from the tonic, and beats).
public struct LessonExample: Codable {
    public let pattern: [Int]
    public let beats: [Float]
}

/// Exercises, studies, tips and lessons. Generated from the Android sources
/// (tools/content-export), so both apps teach exactly the same thing.
public enum Content {
    private struct Payload: Codable {
        let exercises: [Exercise]
        let studies: [Article]
        let tips: [String]
        let lessons: [Lesson]
        let lessonExample: LessonExample
    }

    private static let data: Payload = {
        guard let url = Bundle.module.url(forResource: "content", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: raw)
        else {
            return Payload(exercises: [], studies: [], tips: [""], lessons: [], lessonExample: LessonExample(pattern: [], beats: []))
        }
        return decoded
    }()

    public static var exercises: [Exercise] { data.exercises }
    public static var studies: [Article] { data.studies }
    public static var tips: [String] { data.tips }
    public static var lessons: [Lesson] { data.lessons }
    public static var lessonExample: LessonExample { data.lessonExample }

    public static func exercise(_ id: String) -> Exercise? { data.exercises.first { $0.id == id } }

    public static func lesson(_ mode: HarmonyMode) -> Lesson? { data.lessons.first { $0.mode == mode } }

    /// The same tip all day long.
    public static func tipOfTheDay(_ date: Date = Date()) -> String {
        let days = Int(floor(date.timeIntervalSince1970 / 86400))
        return tips.isEmpty ? "" : tips[floorMod(days, tips.count)]
    }

    /// Exercise categories in the order they first appear.
    public static var categories: [String] {
        var seen: [String] = []
        for e in exercises where !seen.contains(e.category) { seen.append(e.category) }
        return seen
    }
}
