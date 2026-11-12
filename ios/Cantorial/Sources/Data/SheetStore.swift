import CantorialCore
import Foundation
import Observation

/// Chord sheets and setlists saved as one small JSON file. Writes happen off the main thread.
@Observable
final class SheetStore {
    static let shared = SheetStore()

    private(set) var cifras: [Cifra] = []
    private(set) var setlists: [Setlist] = []
    private(set) var loaded = false
    private let io = DispatchQueue(label: "cantorial.cifras", qos: .utility)

    private static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cifras.json")
    }

    private struct Payload: Codable {
        var version = 1
        var cifras: [Cifra]
        var setlists: [Setlist]
    }

    private init() {}

    func load() {
        if loaded { return }
        io.async {
            var payload = Payload(cifras: [], setlists: [])
            if let data = try? Data(contentsOf: SheetStore.file), let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
                payload = decoded
            }
            DispatchQueue.main.async {
                self.cifras = payload.cifras
                self.setlists = payload.setlists
                self.loaded = true
            }
        }
    }

    func find(_ id: String) -> Cifra? { cifras.first { $0.id == id } }

    func findSetlist(_ id: String) -> Setlist? { setlists.first { $0.id == id } }

    func upsert(_ cifra: Cifra) {
        if let i = cifras.firstIndex(where: { $0.id == cifra.id }) {
            if cifras[i] == cifra { return }
            cifras[i] = cifra
        } else {
            cifras.insert(cifra, at: 0)
        }
        save()
    }

    /// Deletes a sheet and takes it out of every setlist.
    func delete(_ id: String) {
        cifras.removeAll { $0.id == id }
        for i in setlists.indices where setlists[i].items.contains(id) {
            setlists[i].items.removeAll { $0 == id }
        }
        save()
    }

    func upsertSetlist(_ setlist: Setlist) {
        if let i = setlists.firstIndex(where: { $0.id == setlist.id }) {
            if setlists[i] == setlist { return }
            setlists[i] = setlist
        } else {
            setlists.insert(setlist, at: 0)
        }
        save()
    }

    func deleteSetlist(_ id: String) {
        setlists.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let snapshot = Payload(cifras: cifras, setlists: setlists)
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: SheetStore.file, options: .atomic)
        }
    }
}
