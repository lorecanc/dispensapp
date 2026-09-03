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

    @State private var showContribute = false
    @State private var contributeName = ""
    @State private var contributeBrands = ""
    @State private var contributeQuantity = ""
    @State private var contributeCategories = ""
    @State private var consentCCBYSA = false
    @State private var contributeLoading = false
    @State private var contributeSuccessMessage: String?
    @State private var contributeError: APIError?

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

            if result.needsEnrichment {
                contributeSection(barcode: barcode)
            }
        }
    }

    @ViewBuilder
    private func contributeSection(barcode: String) -> some View {
        Section("Arricchisci su Open Food Facts") {
            if !showContribute {
                Text("Questo prodotto manca o ha dati incompleti. Puoi contribuire alla community di Open Food Facts inviando nome, marca e altri dati: saranno pubblicati con licenza aperta CC BY-SA / ODbL.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Button("Arricchisci su Open Food Facts") {
                    prefillContribute(from: scanResult)
                    showContribute = true
                }
                .accessibilityLabel("Arricchisci su Open Food Facts")
                .accessibilityHint("Apri il modulo di contribuzione")
            } else {
                TextField("Nome prodotto", text: $contributeName)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Nome prodotto da contribuire")
                TextField("Marca", text: $contributeBrands)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Marca da contribuire")
                TextField("Quantità (es. 500g)", text: $contributeQuantity)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Quantità da contribuire")
                TextField("Categorie (separate da virgola)", text: $contributeCategories, axis: .vertical)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Categorie da contribuire")
                Toggle(isOn: $consentCCBYSA) {
                    Text("Acconsento alla pubblicazione dei dati con licenza CC BY-SA / ODbL su Open Food Facts. Obbligatorio per inviare.")
                        .font(.footnote)
                }
                .accessibilityLabel("Consenso licenza CC BY-SA ODbL")
                .accessibilityHint("Obbligatorio per inviare il contributo")

                if contributeLoading {
                    ProgressView("Invio in corso...")
                        .accessibilityLabel("Invio contributo in corso")
                } else if let message = contributeSuccessMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                        .accessibilityLabel("Contributo inviato: \(message)")
                } else {
                    if let contributeError {
                        Text(contributeError.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Errore contributo: \(contributeError.localizedDescription)")
                    }
                    Button(contributeError == nil ? "Invia contributo" : "Riprova") {
                        Task { await sendContribute(code: barcode) }
                    }
                    .disabled(!consentCCBYSA || contributeLoading || isContributeEmpty)
                    .accessibilityHint("Disponibile solo dopo aver dato il consenso alla licenza")
                    if isContributeEmpty {
                        Text("Inserisci almeno un campo")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    private func prefillContribute(from result: ScanResult?) {
        contributeName = result?.name ?? name
        contributeBrands = result?.brand ?? brand
        if contributeQuantity.isEmpty { contributeQuantity = "" }
        if contributeCategories.isEmpty { contributeCategories = result?.categories.joined(separator: ", ") ?? "" }
        contributeSuccessMessage = nil
        contributeError = nil
    }

    private var isContributeEmpty: Bool {
        [contributeName, contributeBrands, contributeQuantity, contributeCategories].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func sendContribute(code: String) async {
        contributeLoading = true
        contributeError = nil
        contributeSuccessMessage = nil
        do {
            let response = try await store.client.contribute(
                code: code,
                productName: contributeName.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                brands: contributeBrands.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                quantity: contributeQuantity.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                categories: contributeCategories.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                consent: consentCCBYSA
            )
            contributeSuccessMessage = response.message ?? "Contributo inviato, grazie!"
        } catch {
            contributeError = error as? APIError ?? .transport(error)
        }
        contributeLoading = false
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
