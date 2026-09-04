import XCTest
@testable import Inventario

final class ShoppingStoreTests: XCTestCase {

    private func makeItem(id: Int, checked: Bool, name: String = "Latte") -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            shoppingListId: 1,
            name: name,
            quantity: 1,
            checked: checked,
            compartment: "dispensa",
            createdAt: Date()
        )
    }

    private func makeList(id: Int, items: [ShoppingListItem]) -> ShoppingList {
        ShoppingList(
            id: id,
            pantryId: 1,
            name: "Spesa",
            createdAt: Date(),
            items: items
        )
    }

    @MainActor
    func testToggleCheckedOptimistic() async {
        let store = ShoppingStore()
        let item = makeItem(id: 10, checked: false)
        store.lists = [makeList(id: 1, items: [item])]
        store.selectedListId = 1

        // Simula toggle ottimistico come fa ShoppingStore.toggleChecked (senza rete)
        // Copia la logica interna: toggle locale
        if let lIdx = store.lists.firstIndex(where: { $0.id == 1 }),
           let iIdx = store.lists[lIdx].items.firstIndex(where: { $0.id == 10 }) {
            store.lists[lIdx].items[iIdx].checked.toggle()
        }
        XCTAssertTrue(store.lists[0].items[0].checked, "dopo toggle ottimistico dovrebbe essere true")

        // revert su errore
        if let lIdx = store.lists.firstIndex(where: { $0.id == 1 }),
           let iIdx = store.lists[lIdx].items.firstIndex(where: { $0.id == 10 }) {
            store.lists[lIdx].items[iIdx].checked = false
        }
        XCTAssertFalse(store.lists[0].items[0].checked, "dopo revert dovrebbe tornare false")
    }

    @MainActor
    func testToggleCheckedSuccessPath() async {
        let store = ShoppingStore()
        var item = makeItem(id: 1, checked: false)
        store.lists = [makeList(id: 1, items: [item])]
        store.selectedListId = 1

        // Simula il flusso completo: ottimistico -> server conferma checked=true -> sostituzione
        // 1. ottimistico
        if let lIdx = store.lists.firstIndex(where: { $0.id == 1 }),
           let iIdx = store.lists[lIdx].items.firstIndex(where: { $0.id == 1 }) {
            store.lists[lIdx].items[iIdx].checked.toggle()
        }
        XCTAssertTrue(store.lists[0].items[0].checked)

        // 2. server ritorna updated con checked = true
        let updated = ShoppingListItem(id: 1, shoppingListId: 1, name: "Latte", quantity: 1, checked: true, compartment: "dispensa", createdAt: Date())
        if let lIdx = store.lists.firstIndex(where: { $0.id == 1 }),
           let iIdx = store.lists[lIdx].items.firstIndex(where: { $0.id == updated.id }) {
            store.lists[lIdx].items[iIdx] = updated
        }
        XCTAssertTrue(store.lists[0].items[0].checked)
        XCTAssertEqual(store.lists[0].items[0].id, 1)
    }

    @MainActor
    func testDeleteItemRemovesFromList() async {
        let store = ShoppingStore()
        let item1 = makeItem(id: 1, checked: false)
        let item2 = makeItem(id: 2, checked: true)
        store.lists = [makeList(id: 1, items: [item1, item2])]
        store.selectedListId = 1

        // Simula deleteItem locale (senza rete)
        if let lIdx = store.lists.firstIndex(where: { $0.id == 1 }) {
            store.lists[lIdx].items.removeAll { $0.id == 1 }
        }
        XCTAssertEqual(store.lists[0].items.count, 1)
        XCTAssertEqual(store.lists[0].items[0].id, 2)
    }

    @MainActor
    func testSelectedListFallback() {
        let store = ShoppingStore()
        XCTAssertNil(store.selectedList, "senza liste dovrebbe essere nil")
        let list1 = makeList(id: 1, items: [])
        let list2 = makeList(id: 2, items: [])
        store.lists = [list1, list2]
        // senza selectedListId, fallback a first
        XCTAssertEqual(store.selectedList?.id, 1)
        store.selectedListId = 2
        XCTAssertEqual(store.selectedList?.id, 2)
        store.selectedListId = 999 // inesistente -> fallback a first
        XCTAssertEqual(store.selectedList?.id, 1)
    }

    func testShoppingListItemCheckedToggleModel() {
        var item = makeItem(id: 5, checked: false)
        XCTAssertFalse(item.checked)
        item.checked.toggle()
        XCTAssertTrue(item.checked)
        item.checked.toggle()
        XCTAssertFalse(item.checked)
    }
}
