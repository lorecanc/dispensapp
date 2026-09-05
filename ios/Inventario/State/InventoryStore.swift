import Observation
import OSLog
import SwiftUI

// CWE-532: niente print() nei percorsi di rete: os.Logger con
// subsystem = bundle id, categoria "store". Messaggi privi di dati sensibili.
private let storeLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Inventario",
    category: "store"
)

@Observable
@MainActor
final class InventoryStore {
    var items: [InventoryItem] = []
    var pantries: [Pantry] = []
    var history: [Int: [ConsumptionEvent]] = [:]
    // Transitorio locale: ID consumati a zero (remove dalla lista, visibili in Storico via cache).
    var archivedIDs: Set<Int> = []
    var isLoading = false
    var error: APIError?
    var exportedMarkdown: String?

    // Single-owner pantry selection (default 1 personale, persistito). T6 aggiungerà picker UI.
    var selectedPantryId: Int = {
        let stored = UserDefaults.standard.integer(forKey: "selectedPantryId")
        return stored == 0 ? 1 : stored
    }() {
        didSet {
            if oldValue != selectedPantryId {
                UserDefaults.standard.set(selectedPantryId, forKey: "selectedPantryId")
                // Evita leak dati pantry precedente allo switch.
                items = []
                history = [:]
                archivedIDs = []
                exportedMarkdown = nil
                error = nil
            }
        }
    }

    var selectedPantryName: String {
        pantries.first(where: { $0.id == selectedPantryId })?.name ?? "Dispensa"
    }

    let client = APIClient.shared

    // Connettività (T11): monitor drives isOffline; pill UI consumes it (T13).
    let connectivity: ConnectivityMonitor
    var isOffline: Bool { !connectivity.isOnline }

    // Snapshot locale: cold-start con dati eventualmente stantii prima della rete (P4).
    private let cache: LocalInventoryCache

    // Outbox mutazioni offline (T14): FIFO persistente, replay last-write-wins.
    private var outbox: OutboxStore

    // Default costruiti nel body (@MainActor): init di ConnectivityMonitor è actor-isolated
    // e gli argomenti di default verrebbero valutati dal chiamante non isolato.
    init(
        connectivity: ConnectivityMonitor? = nil,
        cache: LocalInventoryCache = LocalInventoryCache(),
        outbox: OutboxStore = OutboxStore()
    ) {
        self.connectivity = connectivity ?? ConnectivityMonitor()
        self.cache = cache
        self.outbox = outbox
        self.connectivity.start()
        startOnlineWatch()
    }

    // Provision single-flight: un solo POST /pantries per token.
    private var isProvisioning = false
    private var provisionAttemptedToken: String?

    func selectPantry(_ id: Int) {
        selectedPantryId = id
    }

    func deletePantry(id: Int) async {
        guard let index = pantries.firstIndex(where: { $0.id == id }) else { return }
        error = nil
        let snapshotPantries = pantries
        let snapshotSelection = selectedPantryId
        let snapshotItems = items
        let snapshotHistory = history
        let snapshotExport = exportedMarkdown
        let wasSelected = (selectedPantryId == id)
        pantries.remove(at: index)
        if wasSelected {
            if let first = pantries.first {
                selectedPantryId = first.id
            } else {
                items = []
                history = [:]
                archivedIDs = []
                exportedMarkdown = nil
            }
        }
        do {
            try await client.deletePantry(id: id)
            // Igiene cache: niente snapshot rivedibile per una pantry morta.
            cache.remove(pantryId: id)
        } catch {
            pantries = snapshotPantries
            selectedPantryId = snapshotSelection
            items = snapshotItems
            history = snapshotHistory
            exportedMarkdown = snapshotExport
            if Task.isCancelled { return }
            setError(from: error)
        }
    }

    func fetchPantries() async {
        do {
            let fetched = try await client.listPantries()
            guard !Task.isCancelled else { return }
            if fetched.isEmpty {
                await ensureProvisionedThenResync()
                return
            }
            pantries = fetched
            // Se la pantry selezionata non esiste più, torna alla prima disponibile.
            if !fetched.contains(where: { $0.id == selectedPantryId }) {
                selectedPantryId = fetched[0].id
            }
            // Gli item si caricano solo per pantry verificate: copre la race del
            // cold-start in cui refresh() parte prima che questa lista arrivi.
            await refresh()
        } catch {
            if Task.isCancelled { return }
            // Solo se lista vuota e 401/403: un tentativo di provision, poi resync.
            if pantries.isEmpty, let apiError = error as? APIError, isAuthFailure(apiError) {
                await ensureProvisionedThenResync()
                return
            }
            // B2: nessun pantry finto. Lista invariata (eventualmente obsoleta);
            // offline tace (pill isOffline), errore vero in banner.
            setError(from: error)
        }
    }

    private func isAuthFailure(_ error: APIError) -> Bool {
        if case .http(let status, _) = error, status == 401 || status == 403 {
            return true
        }
        return false
    }

    // Transienti (network-error/5xx): permettono retry al prossimo fetch.
    // Non-transienti (401/empty, 4xx, decode) restano sticky per-token.
    private func isTransientProvisionError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .transport, .offline:
            return true
        case .http(let status, _):
            return status == 429 || status >= 500
        default:
            return false
        }
    }

    // MARK: - Classificazione offline (O2 + B5)

    /// Codici URLError che significano "rete non raggiungibile" → .offline, non errore generico.
    private static let offlineURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .timedOut,
        .cannotConnectToHost,
        .cannotFindHost,
        .networkConnectionLost,
        .dataNotAllowed,
    ]

    /// Rimappa i trasporti di rete a .offline; altri errori invariati.
    private func classify(_ error: Error) -> APIError {
        let apiError = error as? APIError ?? .transport(error)
        if case .transport(let underlying) = apiError,
           let urlError = underlying as? URLError,
           Self.offlineURLErrorCodes.contains(urlError.code) {
            return .offline
        }
        return apiError
    }

    /// Unico setter di store.error: offline non popola il banner (lo stato è `isOffline`, pill T13).
    private func setError(from error: Error) {
        let apiError = classify(error)
        if case .offline = apiError { return }
        self.error = apiError
    }

    private func ensureProvisionedThenResync() async {
        if isProvisioning { return }
        let token = PantryToken.value
        if provisionAttemptedToken == token {
            // B2: già tentato con questo token: lo stato riflette l'assenza, nessun fake.
            return
        }
        isProvisioning = true
        defer { isProvisioning = false }
        provisionAttemptedToken = token
        do {
            let created = try await client.createPantry(name: "Dispensa")
            guard !Task.isCancelled else { return }
            let refetched = try await client.listPantries()
            guard !Task.isCancelled else { return }
            pantries = refetched.isEmpty ? [created] : refetched
            if !pantries.contains(where: { $0.id == selectedPantryId }) {
                selectedPantryId = pantries[0].id
            }
            await refresh()
        } catch {
            if Task.isCancelled { return }
            let apiError = classify(error)
            if isTransientProvisionError(apiError) { provisionAttemptedToken = nil }
            // B2: nessun pantry finto. Offline: tace (pill); errore vero: in banner.
            if case .offline = apiError { return }
            self.error = apiError
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        // P4: snapshot a disco subito (eventualmente stantio), prima e comunque della rete.
        if items.isEmpty, let snapshot = cache.load(pantryId: selectedPantryId) {
            items = snapshot.items
        }
        // B2: rete solo per pantry verificate (presenti nella lista server):
        // niente 403 a catena su pantry fantasma. fetchPantries() ritenta dopo la verifica.
        guard pantries.contains(where: { $0.id == selectedPantryId }) else { return }
        do {
            let fetched = try await client.listScoped(pantryId: selectedPantryId)
            guard !Task.isCancelled else { return }
            items = fetched.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
            cache.save(items, pantryId: selectedPantryId)
            refreshCategoryRegistry()
        } catch {
            if Task.isCancelled { return }
            setError(from: error)
        }
    }

    /// Best-effort: sync del registry categorie (T10). Non critico: offline resta
    /// il fallback embedded, niente banner. Una volta per sessione, retry se fallito.
    private var categoriesSynced = false

    private func refreshCategoryRegistry() {
        guard !categoriesSynced else { return }
        Task { [client] in
            guard let response = try? await client.fetchCategories() else { return }
            CategoryRegistry.update(with: response)
            categoriesSynced = true
        }
    }

    func add(
        barcode: String,
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        imageURL: String?,
        quantity: Int
    ) async {
        error = nil
        if isOffline {
            enqueueLocalCreate(barcode: barcode, name: name, brand: brand, expirationDate: expirationDate, category: category, imageURL: imageURL, quantity: quantity)
            return
        }
        do {
            let item = try await client.createScoped(
                pantryId: selectedPantryId,
                barcode: barcode,
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                imageURL: imageURL,
                quantity: quantity
            )
            guard !Task.isCancelled else { return }
            items.append(item)
            items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        } catch {
            if Task.isCancelled { return }
            // Rete caduta a metà tentativo: ottimistico + outbox, niente banner.
            if case .offline = classify(error) {
                enqueueLocalCreate(barcode: barcode, name: name, brand: brand, expirationDate: expirationDate, category: category, imageURL: imageURL, quantity: quantity)
                return
            }
            setError(from: error)
        }
    }

    func addManual(
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int
    ) async {
        error = nil
        if isOffline {
            enqueueLocalCreate(barcode: nil, name: name, brand: brand, expirationDate: expirationDate, category: category, imageURL: nil, quantity: quantity)
            return
        }
        do {
            let item = try await client.createManualScoped(
                pantryId: selectedPantryId,
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                quantity: quantity
            )
            guard !Task.isCancelled else { return }
            items.append(item)
            items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        } catch {
            if Task.isCancelled { return }
            if case .offline = classify(error) {
                enqueueLocalCreate(barcode: nil, name: name, brand: brand, expirationDate: expirationDate, category: category, imageURL: nil, quantity: quantity)
                return
            }
            setError(from: error)
        }
    }

    func update(
        id: Int,
        name: String? = nil,
        brand: String? = nil,
        expirationDate: Date? = nil,
        category: String? = nil,
        quantity: Int? = nil
    ) async {
        error = nil
        if isOffline {
            enqueueLocalUpdate(id: id, name: name, brand: brand, expirationDate: expirationDate, category: category, quantity: quantity)
            return
        }
        do {
            let updated = try await client.updateScoped(
                pantryId: selectedPantryId,
                id: id,
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                quantity: quantity
            )
            guard !Task.isCancelled else { return }
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = updated
                items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
            }
        } catch {
            if Task.isCancelled { return }
            if case .offline = classify(error) {
                enqueueLocalUpdate(id: id, name: name, brand: brand, expirationDate: expirationDate, category: category, quantity: quantity)
                return
            }
            setError(from: error)
        }
    }

    func delete(id: Int) async {
        error = nil
        if isOffline {
            enqueueLocalDelete(id: id)
            return
        }
        do {
            try await client.deleteScoped(pantryId: selectedPantryId, id: id)
            guard !Task.isCancelled else { return }
            items.removeAll { $0.id == id }
            history.removeValue(forKey: id)
            archivedIDs.remove(id)
        } catch {
            if Task.isCancelled { return }
            if case .offline = classify(error) {
                enqueueLocalDelete(id: id)
                return
            }
            setError(from: error)
        }
    }

    // Consumo atomico server-side (POST consume). 409 = quantità insufficiente.
    func consume(item: InventoryItem, delta: Int = 1, reason: String? = nil) async {
        error = nil
        if isOffline {
            enqueueLocalConsume(item: item, delta: delta, reason: reason)
            return
        }
        do {
            let updated = try await client.consume(
                pantryId: selectedPantryId, itemId: item.id, delta: delta, reason: reason
            )
            guard !Task.isCancelled else { return }
            if updated.quantity <= 0 {
                items.removeAll { $0.id == item.id }
                archivedIDs.insert(item.id)
            } else if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
                // Lo storico_cached va ricaricato alla prossima apertura.
                history.removeValue(forKey: item.id)
            }
        } catch {
            if Task.isCancelled { return }
            if case .offline = classify(error) {
                enqueueLocalConsume(item: item, delta: delta, reason: reason)
                return
            }
            if case .http(let status, _) = (error as? APIError), status == 409 {
                self.error = .http(status: 409, message: "Quantità insufficiente per \(item.name).")
            } else {
                setError(from: error)
            }
        }
    }

    func decrementQuantity(for item: InventoryItem) async {
        await consume(item: item, delta: 1)
    }

    // MARK: - Outbox offline (T14)

    /// Add/addManual offline: id temporaneo negativo, item visibile subito,
    /// entry in coda. Al replay l'eventuale mapping temp-id→server-id è gestito
    /// da OutboxStore.remapTempId.
    private func enqueueLocalCreate(
        barcode: String?,
        name: String,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        imageURL: String?,
        quantity: Int
    ) {
        let tempId = outbox.nextTempId()
        let item = InventoryItem(
            id: tempId,
            barcode: barcode,
            name: name,
            brand: brand,
            expirationDate: expirationDate,
            isEstimated: false,
            category: category,
            imageURL: imageURL,
            createdAt: Date(),
            quantity: quantity,
            status: "ok"
        )
        items.append(item)
        items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        cache.save(items, pantryId: selectedPantryId)
        outbox.enqueue(
            .create(.init(
                barcode: barcode, name: name, brand: brand,
                expirationDate: expirationDate, category: category,
                imageURL: imageURL, quantity: quantity, tempId: tempId
            )),
            pantryId: selectedPantryId
        )
        triggerReplayIfOnline()
    }

    private func enqueueLocalConsume(item: InventoryItem, delta: Int, reason: String?) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let newQuantity = items[index].quantity - delta
            if newQuantity <= 0 {
                items.removeAll { $0.id == item.id }
                archivedIDs.insert(item.id)
            } else {
                items[index] = items[index].replacing(quantity: newQuantity)
                history.removeValue(forKey: item.id)
            }
        }
        cache.save(items, pantryId: selectedPantryId)
        outbox.enqueue(.consume(.init(itemId: item.id, delta: delta, reason: reason)), pantryId: selectedPantryId)
        triggerReplayIfOnline()
    }

    private func enqueueLocalUpdate(
        id: Int,
        name: String?,
        brand: String?,
        expirationDate: Date?,
        category: String?,
        quantity: Int?
    ) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = items[index].merging(
                name: name, brand: brand, expirationDate: expirationDate,
                category: category, quantity: quantity
            )
            items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        }
        cache.save(items, pantryId: selectedPantryId)
        outbox.enqueue(
            .update(.init(
                itemId: id, name: name, brand: brand,
                expirationDate: expirationDate, category: category, quantity: quantity
            )),
            pantryId: selectedPantryId
        )
        triggerReplayIfOnline()
    }

    private func enqueueLocalDelete(id: Int) {
        items.removeAll { $0.id == id }
        history.removeValue(forKey: id)
        archivedIDs.remove(id)
        cache.save(items, pantryId: selectedPantryId)
        outbox.enqueue(.delete(.init(itemId: id)), pantryId: selectedPantryId)
        triggerReplayIfOnline()
    }

    /// Richiesta finita in outbox con classificazione .offline ma path ancora
    /// satisfied: nessun flip online arriverà a sbloccarla, si riprova subito.
    private func triggerReplayIfOnline() {
        guard connectivity.isOnline else { return }
        Task { await replayOutbox() }
    }

    /// Osserva connectivity.isOnline via withObservationTracking, ri-armandosi a ogni
    /// cambio. La re-arm verifica lo stato corrente (non il flip), quindi nessuna
    /// transizione online può andare persa stabilmente. Il loop termina da solo
    /// quando lo store viene deallocato (weak self).
    private func startOnlineWatch() {
        let monitor = connectivity
        withObservationTracking {
            // Body non isolato: siamo già sul main actor (chiamato da init @MainActor).
            _ = MainActor.assumeIsolated { monitor.isOnline }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if monitor.isOnline {
                    // Recupero da cold-start offline: con pantries vuote refresh() è
                    // inerte (gate B2); fetchPantries() ri-verifica la lista e riconcilia.
                    if self.pantries.isEmpty {
                        await self.fetchPantries()
                    }
                    if !self.outbox.isEmpty {
                        await self.replayOutbox()
                    }
                }
                self.startOnlineWatch()
            }
        }
    }

    private var isReplayingOutbox = false
    /// Richieste di replay arrivate durante un giro in corso: conguagliate in un giro extra.
    private var replayRequested = false

    /// Replay FIFO dell'outbox. Successo → rimuovi entry (e rimappa i temp-id delle
    /// successive); drop (404/409/4xx/decode, vedi OutboxStore.decision) → scarta e
    /// lascia vincere il server; stop (transiente) → fermati, riprova al prossimo
    /// flip online. Mai store.error qui: lo stato è già riflesso nella UI e il
    /// banner risulterebbe fuorviante; dopo lavoro effettivo, refresh() riconcilia.
    func replayOutbox() async {
        guard !isReplayingOutbox else {
            replayRequested = true
            return
        }
        isReplayingOutbox = true
        defer {
            isReplayingOutbox = false
            if replayRequested, connectivity.isOnline {
                replayRequested = false
                Task { await self.replayOutbox() }
            }
        }
        var processedAny = false
        while let entry = outbox.entries.first {
            do {
                let serverId = try await sendOutboxEntry(entry)
                outbox.remove(id: entry.id)
                if case .create(let payload) = entry.mutation, let serverId {
                    outbox.remapTempId(payload.tempId, to: serverId)
                }
                processedAny = true
            } catch let error as APIError {
                switch OutboxStore.decision(for: error) {
                case .stop:
                    return
                case .drop:
                    storeLog.error("outbox \(entry.mutation.kindName, privacy: .public) scartata: \(String(describing: error), privacy: .public)")
                    outbox.remove(id: entry.id)
                    processedAny = true
                }
            } catch {
                return
            }
        }
        if processedAny {
            // Dopo cold-start offline refresh() resterebbe inerte (gate B2):
            // fetchPantries() ri-verifica le pantry e poi riconcilia gli item.
            if pantries.isEmpty {
                await fetchPantries()
            } else {
                await refresh()
            }
        }
    }

    /// Reinvio di una entry sulla sua pantry. Ritorna l'id server per le create
    /// (necessario al remapping dei temp-id), nil per le altre.
    private func sendOutboxEntry(_ entry: OutboxStore.Entry) async throws -> Int? {
        switch entry.mutation {
        case .create(let p):
            let item: InventoryItem
            if let barcode = p.barcode {
                item = try await client.createScoped(
                    pantryId: entry.pantryId, barcode: barcode, name: p.name,
                    brand: p.brand, expirationDate: p.expirationDate,
                    category: p.category, imageURL: p.imageURL, quantity: p.quantity
                )
            } else {
                item = try await client.createManualScoped(
                    pantryId: entry.pantryId, name: p.name, brand: p.brand,
                    expirationDate: p.expirationDate, category: p.category, quantity: p.quantity
                )
            }
            return item.id
        case .consume(let p):
            _ = try await client.consume(
                pantryId: entry.pantryId, itemId: p.itemId, delta: p.delta, reason: p.reason
            )
            return nil
        case .update(let p):
            _ = try await client.updateScoped(
                pantryId: entry.pantryId, id: p.itemId, name: p.name, brand: p.brand,
                expirationDate: p.expirationDate, category: p.category, quantity: p.quantity
            )
            return nil
        case .delete(let p):
            try await client.deleteScoped(pantryId: entry.pantryId, id: p.itemId)
            return nil
        }
    }

    func fetchHistory(itemId: Int) async {
        do {
            let events = try await client.history(pantryId: selectedPantryId, itemId: itemId)
            guard !Task.isCancelled else { return }
            history[itemId] = events
        } catch {
            if Task.isCancelled { return }
            // Storico non critico: 401/403/404 log + cache/[], mai banner errore.
            if let apiError = error as? APIError {
                if case .notFound = apiError {
                    storeLog.info("history non-critical — cache only")
                } else if case .http(let status, _) = apiError, status == 401 || status == 403 || status == 404 {
                    storeLog.info("history non-critical — cache only")
                }
            }
            if history[itemId] == nil {
                history[itemId] = []
            }
        }
    }

    // Inviti/membri (punto 1 UI). Token mai in log, errori o UserDefaults.
    var currentInvite: Invite?
    var inviteLink: String?
    var members: [PantryMember] = []
    var isInviteLoading = false
    var inviteError: APIError?

    func createInvite(pantryId: Int) async {
        isInviteLoading = true
        inviteError = nil
        do {
            let invite = try await client.createInvite(pantryId: pantryId)
            guard !Task.isCancelled else { isInviteLoading = false; return }
            currentInvite = invite
            inviteLink = "inventario://invite?token=\(invite.token)"
        } catch {
            if Task.isCancelled { isInviteLoading = false; return }
            inviteError = error as? APIError ?? .transport(error)
        }
        isInviteLoading = false
    }

    func fetchMembers(pantryId: Int) async {
        isInviteLoading = true
        inviteError = nil
        do {
            let fetched = try await client.listMembers(pantryId: pantryId)
            guard !Task.isCancelled else { isInviteLoading = false; return }
            members = fetched
        } catch {
            if Task.isCancelled { isInviteLoading = false; return }
            inviteError = error as? APIError ?? .transport(error)
        }
        isInviteLoading = false
    }

    // Conferma di rimozione demandata alla UI.
    func removeMember(pantryId: Int, memberToken: String) async {
        isInviteLoading = true
        inviteError = nil
        do {
            try await client.removeMember(pantryId: pantryId, memberToken: memberToken)
            guard !Task.isCancelled else { isInviteLoading = false; return }
            members = try await client.listMembers(pantryId: pantryId)
            guard !Task.isCancelled else { isInviteLoading = false; return }
        } catch {
            if Task.isCancelled { isInviteLoading = false; return }
            inviteError = error as? APIError ?? .transport(error)
        }
        isInviteLoading = false
    }

    func acceptInviteToken(_ token: String) async {
        var sanitized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { sanitized = "" }
        guard !sanitized.isEmpty else { return }
        isInviteLoading = true
        inviteError = nil
        do {
            _ = try await client.acceptInvite(token: sanitized)
            guard !Task.isCancelled else { isInviteLoading = false; return }
            // fetchPantries() verifica la lista e ricarica gli item: niente refresh extra.
            await fetchPantries()
            guard !Task.isCancelled else { isInviteLoading = false; return }
        } catch {
            if Task.isCancelled { isInviteLoading = false; return }
            inviteError = error as? APIError ?? .transport(error)
        }
        isInviteLoading = false
    }

    func exportMarkdown() async {
        error = nil
        do {
            exportedMarkdown = try await client.exportScoped(pantryId: selectedPantryId)
        } catch {
            if Task.isCancelled { return }
            setError(from: error)
        }
    }
}

// MARK: - Copie immutabili per ottimistiche offline (T14)

private extension InventoryItem {
    func replacing(quantity: Int) -> InventoryItem {
        InventoryItem(
            id: id, barcode: barcode, name: name, brand: brand,
            expirationDate: expirationDate, isEstimated: isEstimated,
            category: category, imageURL: imageURL, createdAt: createdAt,
            quantity: quantity, status: status
        )
    }

    /// Merge stile PATCH: i nil lasciano il campo invariato.
    func merging(
        name: String?, brand: String?, expirationDate: Date?,
        category: String?, quantity: Int?
    ) -> InventoryItem {
        InventoryItem(
            id: id, barcode: barcode,
            name: name ?? self.name,
            brand: brand ?? self.brand,
            expirationDate: expirationDate ?? self.expirationDate,
            isEstimated: isEstimated,
            category: category ?? self.category,
            imageURL: imageURL, createdAt: createdAt,
            quantity: quantity ?? self.quantity,
            status: status
        )
    }
}
