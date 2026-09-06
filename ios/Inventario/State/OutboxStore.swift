import Foundation

/// Coda FIFO persistente (JSON su disco) delle mutazioni inventario fatte offline,
/// replay last-write-wins al ritorno della rete (T14). Come LocalInventoryCache:
/// scrittura .atomic, I/O best-effort (un fallimento del disco non deve mai
/// rompere il flusso dati). A differenza degli snapshot, però, vive in
/// Application Support: le entry sono l'unica copia delle mutazioni non ancora
/// synchronize, una directory purgeabile le perderebbe in silenzio.
/// Tipo puro e testabile via `directory`: nessuna dipendenza da rete/MainActor.
struct OutboxStore {
    // MARK: - Mutazioni

    enum Mutation: Codable, Equatable {
        /// add/addManual: barcode nil → create manuale. tempId = id locale negativo.
        struct Create: Codable, Equatable {
            let barcode: String?
            let name: String
            let brand: String?
            let expirationDate: Date?
            let category: String?
            let imageURL: String?
            let quantity: Int
            let tempId: Int
            /// Campi additivi (T11): entry vecchie su disco senza chiavi → nil,
            /// il replay le invia identiche ai valori pre-upgrade.
            var offTags: [String]? = nil
            var storageLocation: String? = nil
            /// Campi additivi (T8c): come sopra, entry vecchie senza chiavi → nil.
            var source: String? = nil
            var productType: String? = nil
        }
        struct Consume: Codable, Equatable {
            var itemId: Int
            let delta: Int
            let reason: String?
        }
        /// PATCH: campi nil = non toccati (stessa semantica di APIClient.updateScoped).
        struct Update: Codable, Equatable {
            var itemId: Int
            let name: String?
            let brand: String?
            let expirationDate: Date?
            let category: String?
            let quantity: Int?
        }
        struct Delete: Codable, Equatable {
            var itemId: Int
        }

        case create(Create)
        case consume(Consume)
        case update(Update)
        case delete(Delete)

        var kindName: String {
            switch self {
            case .create: "create"
            case .consume: "consume"
            case .update: "update"
            case .delete: "delete"
            }
        }
    }

    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let createdAt: Date
        /// Pantry di appartenenza: il replay usa questo id, non la selezione corrente
        /// (l'utente può cambiare pantry tra mutazione e sync).
        let pantryId: Int
        var mutation: Mutation
    }

    /// Politica di replay per una entry fallita (puramente statica, testabile).
    enum ReplayDecision: Equatable {
        /// Entry scartabile: lo stato server vince (404/409, altri 4xx, decode).
        case drop
        /// Transiente/incerto: fermare il replay, riprovare al prossimo evento online.
        case stop
    }

    static func decision(for error: APIError) -> ReplayDecision {
        switch error {
        case .notFound:
            return .drop
        case .http(let status, _):
            // 401/403 (auth), 408/429 (transienti): stop, la entry resta in coda.
            if status == 401 || status == 403 || status == 408 || status == 429 {
                return .stop
            }
            // Qualsiasi altro 4xx = la richiesta non passerà mai: drop (404/409 = conflitti,
            // altri 4xx = scarto documentato: l'azione era già riflessa nella UI).
            return (400...499).contains(status) ? .drop : .stop
        case .decoding:
            // Risposta non interpretabile ma il server potrebbe aver applicato: la
            // riconciliazione via refresh() vince sull'entry locale.
            return .drop
        case .transport, .offline, .invalidURL:
            return .stop
        }
    }

    // MARK: - Persistenza

    private struct Contents: Codable {
        /// Contatore negativi monotòno, persistito: nessun riutilizzo di temp-id
        /// nemmeno dopo che le entry sono state replayate.
        var nextTempId: Int = -1
        var entries: [Entry] = []
    }

    /// Directory del JSON di coda. Non-`private` per il test che asserisce la
    /// posizione di default (Application Support, non Caches purgeabile).
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            // Application Support (non purgeabile): la coda è l'unica copia delle
            // mutazioni non sincronizzate, Caches rischierebbe la perdita silenziosa.
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appending(path: "InventarioOutbox", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private var fileURL: URL {
        directory.appending(path: "outbox.json")
    }

    /// Entry in ordine FIFO (la prima è la più vecchia).
    var entries: [Entry] { load().entries }

    var count: Int { entries.count }

    var isEmpty: Bool { entries.isEmpty }

    /// Alloca l'id temporaneo negativo successivo (-1, -2, …) e persiste il contatore
    /// subito, così il riavvio dell'app non rieseverà mai un temp-id già assegnato.
    mutating func nextTempId() -> Int {
        var contents = load()
        let id = contents.nextTempId
        contents.nextTempId -= 1
        save(contents)
        return id
    }

    @discardableResult
    mutating func enqueue(_ mutation: Mutation, pantryId: Int, now: Date = Date()) -> Entry {
        var contents = load()
        let entry = Entry(id: UUID(), createdAt: now, pantryId: pantryId, mutation: mutation)
        contents.entries.append(entry)
        save(contents)
        return entry
    }

    mutating func remove(id: UUID) {
        var contents = load()
        contents.entries.removeAll { $0.id == id }
        save(contents)
    }

    /// Dopo il replay riuscito di una create, aggiorna le entry successive che
    /// referenziano il temp-id (es. consume su item creato offline) con l'id server.
    /// La entry create stessa non viene toccata (già rimossa dal chiamante).
    mutating func remapTempId(_ tempId: Int, to serverId: Int) {
        var contents = load()
        var changed = false
        for index in contents.entries.indices {
            var remapped = false
            switch contents.entries[index].mutation {
            case .create:
                break
            case .consume(var payload):
                if payload.itemId == tempId {
                    payload.itemId = serverId
                    contents.entries[index].mutation = .consume(payload)
                    remapped = true
                }
            case .update(var payload):
                if payload.itemId == tempId {
                    payload.itemId = serverId
                    contents.entries[index].mutation = .update(payload)
                    remapped = true
                }
            case .delete(var payload):
                if payload.itemId == tempId {
                    payload.itemId = serverId
                    contents.entries[index].mutation = .delete(payload)
                    remapped = true
                }
            }
            changed = changed || remapped
        }
        if changed { save(contents) }
    }

    // MARK: - Private I/O

    /// File mancante o corrotto → coda vuota (il corrotto viene rimosso).
    private func load() -> Contents {
        guard let data = try? Data(contentsOf: fileURL) else { return Contents() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let contents = try? decoder.decode(Contents.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return Contents()
        }
        return contents
    }

    private func save(_ contents: Contents) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(contents) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // best-effort: la coda in memoria vive comunque fino al prossimo tentativo.
        }
    }
}
