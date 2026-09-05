import Foundation

/// Snapshot su disco (JSON in Caches) della lista item di una pantry.
/// Scopo: cold-start istantaneo con dati eventualmente stantii (P4) e consultazione
/// offline dell'ultimo stato noto. Uno file per pantry id.
/// Tipo puro, testabile via `directory`; I/O best-effort: un fallimento del cache
/// non deve mai rompere il flusso dati.
struct LocalInventoryCache {
    struct Snapshot: Codable, Equatable {
        let pantryId: Int
        let savedAt: Date
        let items: [InventoryItem]
    }

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            // Caches: contenuto rigenerabile dal server, eliminabile dal sistema senza perdita.
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appending(path: "InventarioSnapshots", directoryHint: .isDirectory)
        }
    }

    /// Carica lo snapshot della pantry. File mancante o corrotto → nil (e il corrotto viene rimosso).
    func load(pantryId: Int) -> Snapshot? {
        let url = fileURL(for: pantryId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.pantryId == pantryId else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    /// Sostituisce lo snapshot della pantry con `items`.
    @discardableResult
    func save(_ items: [InventoryItem], pantryId: Int, savedAt: Date = Date()) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(Snapshot(pantryId: pantryId, savedAt: savedAt, items: items)) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: pantryId), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Elimina lo snapshot (es. pantry rimossa: niente dati fantasma rivedibili).
    func remove(pantryId: Int) {
        try? FileManager.default.removeItem(at: fileURL(for: pantryId))
    }

    private func fileURL(for pantryId: Int) -> URL {
        directory.appending(path: "pantry-\(pantryId).json")
    }
}
