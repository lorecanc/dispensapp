import SwiftUI

@main
struct InventarioApp: App {
    @State private var store = InventoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
