import SwiftUI

struct ScanPreviewSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let barcode: String

    @State private var scanResult: ScanResult?
    @State private var isLoading = true
    @State private var error: APIError?

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var selectedCategory: String = ""
    @State private var expirationDate = Date().addingTimeInterval(86400 * 30)
    @State private var quantity = 1
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let client = APIClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Caricamento...")
                } else if let error {
                    ContentUnavailableView(
                        "Errore",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else if let result = scanResult {
                    formView(result: result)
                }
            }
            .navigationTitle("Prodotto scansionato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task { await saveItem() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task {
                await loadScanResult()
            }
            .alert("Errore", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private func formView(result: ScanResult) -> some View {
        Form {
            if let imageURL = result.imageURL, let url = URL(string: imageURL) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.secondary.opacity(0.2))
                                .frame(height: 120)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.secondary.opacity(0.2))
                                .frame(height: 120)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !result.found {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Prodotto non trovato", systemImage: "exclamationmark.magnifyingglass")
                            .foregroundStyle(.orange)
                            .font(.headline)
                        Text(result.message ?? "Inserisci i dati manualmente.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Dettagli") {
                HStack {
                    Text("Codice a barre")
                    Spacer()
                    Text(barcode)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }

                TextField("Nome *", text: $name)
                    .autocorrectionDisabled()

                TextField("Marca", text: $brand)
                    .autocorrectionDisabled()
            }

            Section {
                CategoryPicker(selection: $selectedCategory)
                DatePicker("Data di scadenza", selection: $expirationDate, displayedComponents: .date)
                QuantityStepper(quantity: $quantity)
            }
        }
    }

    private func loadScanResult() async {
        isLoading = true
        do {
            let result = try await client.scan(barcode: barcode)
            scanResult = result
            name = result.name ?? ""
            brand = result.brand ?? ""
            let rawCategory = result.categories.first ?? ""
            selectedCategory = CategoryPicker.validCategoryKeys.contains(rawCategory) ? rawCategory : ""
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
        isLoading = false
    }

    private func saveItem() async {
        isSaving = true
        await store.add(
            barcode: barcode,
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            expirationDate: expirationDate,
            category: selectedCategory.nilIfEmpty,
            imageURL: scanResult?.imageURL,
            quantity: quantity
        )
        isSaving = false
        if let error = store.error {
            errorMessage = error.localizedDescription
            showError = true
        } else {
            dismiss()
        }
    }
}
