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

    let client = APIClient.shared

    var selectedList: ShoppingList? {
        guard let id = selectedListId else { return lists.first }
        return lists.first(where: { $0.id == id }) ?? lists.first
    }

    // MARK: - Lists

    func fetchLists(pantryId: Int) async {
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
            self.error = error as? APIError ?? .transport(error)
        }
        isLoading = false
    }

    func createList(pantryId: Int, name: String = "Spesa") async {
        error = nil
        do {
            let created = try await client.createShoppingList(pantryId: pantryId, name: name)
            lists.append(created)
            selectedListId = created.id
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func deleteShoppingList(pantryId: Int, id: Int) async {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        error = nil
        let snapshotLists = lists
        let snapshotSelection = selectedListId
        lists.remove(at: index)
        if selectedListId == id {
            selectedListId = lists.first?.id
        }
        do {
            try await client.deleteShoppingList(pantryId: pantryId, listId: id)
        } catch {
            lists = snapshotLists
            selectedListId = snapshotSelection
            if Task.isCancelled { return }
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func fetchItems(pantryId: Int, listId: Int) async {
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

    func addItem(pantryId: Int, name: String, quantity: Int, compartment: String?) async {
        guard let listId = selectedList?.id else {
            // Auto-crea lista se mancante
            await createList(pantryId: pantryId)
            guard let newId = selectedList?.id else { return }
            await addItemToList(pantryId: pantryId, listId: newId, name: name, quantity: quantity, compartment: compartment)
            return
        }
        await addItemToList(pantryId: pantryId, listId: listId, name: name, quantity: quantity, compartment: compartment)
    }

    private func addItemToList(pantryId: Int, listId: Int, name: String, quantity: Int, compartment: String?) async {
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

    func toggleChecked(pantryId: Int, item: ShoppingListItem) async {
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

    func deleteItem(pantryId: Int, itemId: Int) async {
        guard let listId = selectedList?.id else { return }
        error = nil
        do {
            try await client.deleteShoppingItem(pantryId: pantryId, listId: listId, itemId: itemId)
            if let lIdx = lists.firstIndex(where: { $0.id == listId }) {
                lists[lIdx].items.removeAll { $0.id == itemId }
            }
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    // MARK: - Export

    func exportMarkdown(pantryId: Int) async {
        guard let listId = selectedList?.id else { return }
        error = nil
        do {
            exportedMarkdown = try await client.exportShoppingMarkdown(pantryId: pantryId, listId: listId)
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
