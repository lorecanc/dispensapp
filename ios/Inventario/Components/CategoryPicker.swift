import SwiftUI

struct CategoryPicker: View {
    @Binding var selection: String

    private let categories: [(key: String, label: String)] = [
        ("yogurt", "Yogurt"),
        ("fresh-milk", "Latte fresco"),
        ("pasta", "Pasta"),
        ("canned-vegetables", "Verdure in scatola"),
        ("rice", "Riso"),
        ("cheeses", "Formaggi"),
        ("eggs", "Uova"),
        ("fresh-fruits", "Frutta fresca"),
        ("fresh-vegetables", "Verdura fresca"),
        ("frozen-foods", "Surgelati"),
    ]

    static let validCategoryKeys: Set<String> = [
        "yogurt", "fresh-milk", "pasta", "canned-vegetables",
        "rice", "cheeses", "eggs", "fresh-fruits",
        "fresh-vegetables", "frozen-foods",
    ]

    var body: some View {
        Picker("Categoria", selection: $selection) {
            Text("Nessuna").tag("")
            ForEach(categories, id: \.key) { cat in
                Text(cat.label).tag(cat.key)
            }
        }
    }
}
