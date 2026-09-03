import SwiftUI

struct ContentView: View {
    var body: some View {
        tabContent
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 26.0, *) {
            TabView {
                Tab("Dispensa", systemImage: "refrigerator") {
                    NavigationStack {
                        InventoryListView()
                    }
                }
                Tab("Spesa", systemImage: "cart") {
                    NavigationStack {
                        ShoppingListView()
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18.0, *) {
            TabView {
                Tab("Dispensa", systemImage: "refrigerator") {
                    NavigationStack {
                        InventoryListView()
                    }
                }
                Tab("Spesa", systemImage: "cart") {
                    NavigationStack {
                        ShoppingListView()
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView {
                NavigationStack {
                    InventoryListView()
                }
                .tabItem {
                    Label("Dispensa", systemImage: "refrigerator")
                }

                NavigationStack {
                    ShoppingListView()
                }
                .tabItem {
                    Label("Spesa", systemImage: "cart")
                }
            }
        }
    }
}
