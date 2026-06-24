import SwiftUI

@Observable
@MainActor
final class InventoryStore {
    var items: [InventoryItem] = []
    var isLoading = false
    var error: APIError?
    var exportedMarkdown: String?

    private let client = APIClient()

    func refresh() async {
        isLoading = true
        error = nil
        do {
            items = try await client.list()
        } catch {
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
            let item = try await client.create(
                barcode: barcode,
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                imageURL: imageURL,
                quantity: quantity
            )
            items.append(item)
            items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        } catch {
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
            let item = try await client.createManual(
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                quantity: quantity
            )
            items.append(item)
            items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        } catch {
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
            let updated = try await client.update(
                id: id,
                name: name,
                brand: brand,
                expirationDate: expirationDate,
                category: category,
                quantity: quantity
            )
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = updated
            }
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func delete(id: Int) async {
        error = nil
        do {
            try await client.delete(id: id)
            items.removeAll { $0.id == id }
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }

    func decrementQuantity(for item: InventoryItem) async {
        if item.quantity > 1 {
            await update(id: item.id, quantity: item.quantity - 1)
        } else {
            await delete(id: item.id)
        }
    }

    func exportMarkdown() async {
        error = nil
        do {
            exportedMarkdown = try await client.exportMarkdown()
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
    }
}
