import Foundation

@Observable
@MainActor
final class ShoppingStore {
    var lists: [ShoppingList] = []
    var selectedListId: Int?
    var isLoading = false
    var error: APIError?
    var exportedMarkdown: String?
    var suggestions: [Suggestion] = []
    var pantryChecks: [Int: PantryCheckItem] = [:]

    let client = APIClient.shared
    // Single selection condivisa via UserDefaults (default 1 personale, owner InventoryStore).
    // Replica locale per plumbing T5; T6 aggiungerà picker UI.
    var selectedPantryId: Int = {
        let stored = UserDefaults.standard.integer(forKey: "selectedPantryId")
        return stored == 0 ? 1 : stored
    }() {
        didSet {
            if oldValue != selectedPantryId {
                UserDefaults.standard.set(selectedPantryId, forKey: "selectedPantryId")
                // Evita leak dati pantry precedente allo switch.
                lists = []
                selectedListId = nil
                pantryChecks = [:]
                suggestions = []
                exportedMarkdown = nil
                error = nil
            }
        }
    }

    func selectPantry(_ id: Int) {
        selectedPantryId = id
    }

    // Alias compat: tutto il networking usa selectedPantryId.
    var pantryId: Int { selectedPantryId }

    var selectedList: ShoppingList? {
        guard let id = selectedListId else { return lists.first }
        return lists.first(where: { $0.id == id }) ?? lists.first
    }

    // MARK: - Lists

    func fetchLists() async {
        isLoading = true
        error = nil
        do {
            let fetched = try await client.listShoppingLists(pantryId: pantryId)
            guard !Task.isCancelled else { isLoading = false; return }
            lists = fetched
            if selectedListId == nil { selectedListId = fetched.first?.id }
            else if let sel = selectedListId, !fetched.contains(where: { $0.id == sel }) {
                selectedListId = fetched.first?.id
            }
        } catch {
            if Task.isCancelled { isLoading = false; return }
            let apiError = error as? APIError ?? .transport(error)
            // Hint già in APIError (401 -> "Token mancante"); logga per debug senza token value.
            if case .http(let status, _) = apiError, status == 401 {
                print("[ShoppingStore] 401 per pantry \(pantryId) — verifica header auth")
            }
            if case .notFound = apiError {
                print("[ShoppingStore] Pantry \(pantryId) non trovata — log only")
            }
            if case .http(let status, _) = apiError, status == 404 {
                print("[ShoppingStore] Pantry \(pantryId) 404 — come sopra, log only")
            }
            if case .http(let status, _) = apiError, status == 403 {
                print("[ShoppingStore] 403 non membro pantry \(pantryId) — log only")
            }
            self.error = apiError
        }
        isLoading = false
    }

    func createList(name: String = "Spesa") async {
        error = nil
        do {
            let created = try await client.createShoppingList(pantryId: pantryId, name: name)
            lists.append(created)
            selectedListId = created.id
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func fetchItems(listId: Int) async {
        error = nil
        do {
            let refreshed = try await client.getShoppingList(pantryId: pantryId, listId: listId)
            guard !Task.isCancelled else { return }
            if let idx = lists.firstIndex(where: { $0.id == listId }) {
                lists[idx] = refreshed
            } else {
                lists.append(refreshed)
            }
        } catch {
            if Task.isCancelled { return }
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // MARK: - Items

    func addItem(name: String, quantity: Int, compartment: String?) async {
        guard let listId = selectedList?.id else {
            // Auto-crea lista se mancante
            await createList()
            guard let newId = selectedList?.id else { return }
            await addItemToList(listId: newId, name: name, quantity: quantity, compartment: compartment)
            return
        }
        await addItemToList(listId: listId, name: name, quantity: quantity, compartment: compartment)
    }

    private func addItemToList(listId: Int, name: String, quantity: Int, compartment: String?) async {
        error = nil
        do {
            let item = try await client.addShoppingItem(
                pantryId: pantryId, listId: listId, name: name, quantity: quantity, compartment: compartment
            )
            if let idx = lists.firstIndex(where: { $0.id == listId }) {
                lists[idx].items.append(item)
            }
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func toggleChecked(item: ShoppingListItem) async {
        guard let listId = selectedList?.id else { return }
        // Toggle ottimistico per UI reattiva, revert su errore
        if let lIdx = lists.firstIndex(where: { $0.id == listId }),
           let iIdx = lists[lIdx].items.firstIndex(where: { $0.id == item.id }) {
            lists[lIdx].items[iIdx].checked.toggle()
        }
        do {
            let updated = try await client.toggleShoppingItem(
                pantryId: pantryId, listId: listId, itemId: item.id, checked: !item.checked
            )
            if let lIdx = lists.firstIndex(where: { $0.id == listId }),
               let iIdx = lists[lIdx].items.firstIndex(where: { $0.id == updated.id }) {
                lists[lIdx].items[iIdx] = updated
            }
        } catch {
            // revert
            if let lIdx = lists.firstIndex(where: { $0.id == listId }),
               let iIdx = lists[lIdx].items.firstIndex(where: { $0.id == item.id }) {
                lists[lIdx].items[iIdx].checked = item.checked
            }
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func deleteItem(itemId: Int) async {
        guard let listId = selectedList?.id else { return }
        error = nil
        do {
            try await client.deleteShoppingItem(pantryId: pantryId, listId: listId, itemId: itemId)
            if let lIdx = lists.firstIndex(where: { $0.id == listId }) {
                lists[lIdx].items.removeAll { $0.id == itemId }
                pantryChecks.removeValue(forKey: itemId)
            }
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // MARK: - Export

    func exportMarkdown() async {
        guard let listId = selectedList?.id else { return }
        error = nil
        do {
            exportedMarkdown = try await client.exportShoppingMarkdown(pantryId: pantryId, listId: listId)
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // MARK: - Check pantry cross

    func checkInPantry() async {
        guard let listId = selectedList?.id else { return }
        error = nil
        do {
            let results = try await client.checkShoppingList(pantryId: pantryId, listId: listId)
            var map: [Int: PantryCheckItem] = [:]
            for r in results { map[r.id] = r }
            pantryChecks = map
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // MARK: - Suggestions

    func fetchSuggestions(q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        do {
            suggestions = try await client.fetchSuggestions(q: trimmed)
        } catch {
            // suggerimenti non critici: non sovrascrivere error principale
            suggestions = []
        }
    }
}
