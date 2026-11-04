import CantorialCore
import Foundation
import Observation

struct Song: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// File name of the imported audio inside the app's Audio folder.
    var audioFile: String?
    var notes: [NoteEvent]
    var key: Key
    var mode: HarmonyMode
    var octave: Int
    var createdAt: Date
    var durationMs: Int
    /// Practising the second voice (false) or backing vocals (true).
    var backingMode = false
    /// Voice type of the lead singer (regente) for backing vocals; nil = same as the user.
    var leadVoice: VoiceType?
    var backingStyle: BackingStyle = .harmony
    var backingVoices = 1
    var backingPart = 0

    var audioURL: URL? { audioFile.map { SongStore.audioFolder.appendingPathComponent($0) } }
}

/// Songs saved as one small JSON file in the app's documents. Writes happen off the main thread.
@Observable
final class SongStore {
    static let shared = SongStore()

    private(set) var songs: [Song] = []
    private(set) var loaded = false
    private let io = DispatchQueue(label: "cantorial.songs", qos: .utility)

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var file: URL { documents.appendingPathComponent("songs.json") }
    static var audioFolder: URL { documents.appendingPathComponent("Audio", isDirectory: true) }

    private struct Payload: Codable {
        var version = 1
        var songs: [Song]
    }

    private init() {}

    func load() {
        if loaded { return }
        io.async {
            var list: [Song] = []
            if let data = try? Data(contentsOf: SongStore.file) {
                let decoder = JSONDecoder()
                list = (try? decoder.decode(Payload.self, from: data))?.songs ?? []
            }
            DispatchQueue.main.async {
                self.songs = list
                self.loaded = true
            }
        }
    }

    func find(_ id: String) -> Song? { songs.first { $0.id == id } }

    func upsert(_ song: Song) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            if songs[i] == song { return }
            songs[i] = song
        } else {
            songs.insert(song, at: 0)
        }
        save()
    }

    func delete(_ id: String) {
        if let song = find(id), let url = song.audioURL, !songs.contains(where: { $0.id != id && $0.audioFile == song.audioFile }) {
            try? FileManager.default.removeItem(at: url)
        }
        songs.removeAll { $0.id == id }
        save()
    }

    /// Copies a picked audio file into the app, so it stays playable. Returns its file name.
    static func importAudio(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let name = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: source, to: audioFolder.appendingPathComponent(name))
        return name
    }

    private func save() {
        let snapshot = Payload(songs: songs)
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: SongStore.file, options: .atomic)
        }
    }
}
