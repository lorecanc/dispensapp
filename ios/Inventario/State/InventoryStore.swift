import SwiftUI

@Observable
@MainActor
final class InventoryStore {
    var items: [InventoryItem] = []
    var pantries: [Pantry] = []
    var history: [Int: [ConsumptionEvent]] = [:]
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
                exportedMarkdown = nil
                error = nil
            }
        }
    }

    var selectedPantryName: String {
        pantries.first(where: { $0.id == selectedPantryId })?.name ?? "Dispensa"
    }

    let client = APIClient.shared

    // Provision single-flight: un solo POST /pantries per token.
    private var isProvisioning = false
    private var provisionAttemptedToken: String?

    func selectPantry(_ id: Int) {
        selectedPantryId = id
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
        } catch {
            if Task.isCancelled { return }
            // Solo se lista vuota e 401/403: un tentativo di provision, poi resync.
            if pantries.isEmpty, let apiError = error as? APIError, isAuthFailure(apiError) {
                await ensureProvisionedThenResync()
                return
            }
            // Non critico: la lista resta vuota e il picker mostra fallback.
            if pantries.isEmpty { pantries = [Pantry(id: selectedPantryId, name: "Dispensa", createdAt: Date())] }
        }
    }

    private func isAuthFailure(_ error: APIError) -> Bool {
        if case .http(let status, _) = error, status == 401 || status == 403 {
            return true
        }
        return false
    }

    private func ensureProvisionedThenResync() async {
        if isProvisioning { return }
        let token = PantryToken.value
        if provisionAttemptedToken == token {
            if pantries.isEmpty { pantries = [Pantry(id: selectedPantryId, name: "Dispensa", createdAt: Date())] }
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
        } catch {
            if Task.isCancelled { return }
            if pantries.isEmpty { pantries = [Pantry(id: selectedPantryId, name: "Dispensa", createdAt: Date())] }
        }
    }

    func refresh() async {
        isLoading = true
        error = nil
        do {
            let fetched = try await client.listScoped(pantryId: selectedPantryId)
            guard !Task.isCancelled else { isLoading = false; return }
            items = fetched.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        } catch {
            if Task.isCancelled { isLoading = false; return }
            self.error = error as? APIError ?? .transport(error)
        }
        isLoading = false
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
            self.error = error as? APIError ?? .transport(error)
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
            self.error = error as? APIError ?? .transport(error)
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
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func delete(id: Int) async {
        error = nil
        do {
            try await client.deleteScoped(pantryId: selectedPantryId, id: id)
            guard !Task.isCancelled else { return }
            items.removeAll { $0.id == id }
            history.removeValue(forKey: id)
        } catch {
            if Task.isCancelled { return }
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // Consumo atomico server-side (POST consume). 409 = quantità insufficiente.
    func consume(item: InventoryItem, delta: Int = 1, reason: String? = nil) async {
        error = nil
        do {
            let updated = try await client.consume(
                pantryId: selectedPantryId, itemId: item.id, delta: delta, reason: reason
            )
            guard !Task.isCancelled else { return }
            if updated.quantity <= 0 {
                items.removeAll { $0.id == item.id }
                history.removeValue(forKey: item.id)
            } else if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
            // Lo storico_cached va ricaricato alla prossima espansione.
            history.removeValue(forKey: item.id)
        } catch {
            if Task.isCancelled { return }
            if case .http(let status, _) = (error as? APIError), status == 409 {
                self.error = .http(status: 409, message: "Quantità insufficiente per \(item.name).")
            } else {
                self.error = error as? APIError ?? .transport(error)
            }
        }
    }

    func decrementQuantity(for item: InventoryItem) async {
        await consume(item: item, delta: 1)
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
                    print("[InventoryStore] history non-critical — cache only")
                } else if case .http(let status, _) = apiError, status == 401 || status == 403 || status == 404 {
                    print("[InventoryStore] history non-critical — cache only")
                }
            }
            if history[itemId] == nil {
                history[itemId] = []
            }
        }
    }

    func exportMarkdown() async {
        error = nil
        do {
            exportedMarkdown = try await client.exportScoped(pantryId: selectedPantryId)
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }
}
