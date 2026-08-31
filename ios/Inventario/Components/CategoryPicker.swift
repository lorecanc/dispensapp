import SwiftUI

struct CategoryPicker: View {
    @Binding var selection: String

    private let categories = CategoryRegistry.categories

    /// Forwarded for backward compatibility — single source is CategoryRegistry.
    static let validCategoryKeys: Set<String> = CategoryRegistry.validCategoryKeys

    var body: some View {
        Picker("Categoria", selection: $selection) {
            Text("Nessuna").tag("")
            ForEach(categories, id: \.key) { cat in
                Text(cat.label).tag(cat.key)
            }
        }
    }
}
