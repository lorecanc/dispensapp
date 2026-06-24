import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "La tua dispensa è vuota",
            systemImage: "refrigerator",
            description: Text("Tocca + per aggiungere un prodotto.")
        )
    }
}
