import SwiftUI

struct ScanPreviewSheet: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let barcode: String
    var result: ScanResult? = nil

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

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Caricamento...")
                        .accessibilityLabel("Caricamento prodotto")
                        .dynamicTypeSize(.xSmall ... .accessibility2)
                } else if let error {
                    ContentUnavailableView(
                        "Errore",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                    .accessibilityLabel("Errore \(error.localizedDescription)")
                    .dynamicTypeSize(.xSmall ... .accessibility2)
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
                    Group {
                        if #available(iOS 26.0, *) {
                            Button("Salva") {
                                Task { await saveItem() }
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Color.pantryMoss)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        } else {
                            Button("Salva") {
                                Task { await saveItem() }
                            }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        }
                    }
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
                                .fill(Color.pantryOat.opacity(0.35))
                                .frame(height: 120)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(Color.textSecondary)
                                        .accessibilityHidden(true)
                                }
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.pantryOat.opacity(0.25))
                                .frame(height: 120)
                                .overlay {
                                    ProgressView()
                                        .tint(Color.pantryMoss)
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
                            .foregroundStyle(Color.statusSoon)
                            .font(.headline)
                            .accessibilityLabel("Prodotto non trovato")
                            .accessibilityHint("Inserisci i dati manualmente")
                        Text(result.message ?? "Inserisci i dati manualmente.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Dettagli") {
                HStack {
                    Text("Codice a barre")
                    Spacer()
                    Text(barcode)
                        .foregroundStyle(Color.textSecondary)
                        .monospaced()
                        .accessibilityLabel("Codice a barre \(barcode)")
                }
                .accessibilityElement(children: .combine)

                TextField("Nome *", text: $name)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Nome prodotto")
                    .accessibilityHint("Campo obbligatorio")

                TextField("Marca", text: $brand)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Marca")
            }

            Section {
                CategoryPicker(selection: $selectedCategory)
                DatePicker("Data di scadenza", selection: $expirationDate, displayedComponents: .date)
                QuantityStepper(quantity: $quantity)
            }
        }
    }

    private func loadScanResult() async {
        print("[ScanPreview] loadScanResult for barcode:", barcode)
        if let result {
            apply(result)
            isLoading = false
            return
        }
        isLoading = true
        do {
            let result = try await store.client.scan(barcode: barcode)
            apply(result)
        } catch {
            self.error = error as? APIError ?? .transport(error)
        }
        isLoading = false
    }

    private func apply(_ result: ScanResult) {
        scanResult = result
        name = result.name ?? ""
        brand = result.brand ?? ""
        let rawCategory = result.categories.first ?? ""
        selectedCategory = CategoryRegistry.validCategoryKeys.contains(rawCategory) ? rawCategory : ""
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
