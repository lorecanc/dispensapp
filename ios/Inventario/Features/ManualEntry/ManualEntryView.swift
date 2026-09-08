import SwiftUI

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ManualEntryView: View {
    @Environment(InventoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var selectedCategory: String = ""
    @State private var selectedStorage: String = ""
    @State private var storageTouched = false
    @State private var expirationDate = Date().addingTimeInterval(86400 * 30)
    @State private var quantity = 1
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var suggestions: [Suggestion] = []

    /// Prefill da tap su suggerimento dispensa (InventoryListView).
    /// Default vuoti: i call site esistenti restano invariati.
    let initialName: String
    let initialCategory: String

    init(initialName: String = "", initialCategory: String = "") {
        self.initialName = initialName
        self.initialCategory = initialCategory
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Dettagli prodotto") {
                TextField("Nome *", text: $name)
                    .autocorrectionDisabled()

                if !suggestions.isEmpty {
                    ForEach(suggestions) { sug in
                        Button {
                            name = sug.name
                            if let cat = sug.category, !cat.isEmpty {
                                selectedCategory = cat
                                storageTouched = false
                            }
                            suggestions = []
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sug.name)
                                        .foregroundStyle(Color.textPrimary)
                                        .font(.subheadline.weight(.medium))
                                    if let cat = sug.category {
                                        Text(CategoryRegistry.displayName(for: cat))
                                            .font(.caption)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                                Spacer()
                                Text("×\(sug.timesScanned)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }

                TextField("Marca", text: $brand)
                    .autocorrectionDisabled()
            }

            Section {
                CategoryPicker(selection: $selectedCategory)
                Picker("Conservazione", selection: storageBinding) {
                    ForEach(CategoryRegistry.storageCodes, id: \.self) { code in
                        Label {
                            Text(CategoryRegistry.storageLabel(for: code))
                        } icon: {
                            if let icon = CategoryRegistry.storageIcon(for: code) {
                                Image(systemName: icon)
                            }
                        }
                        .tag(code)
                    }
                }
                .accessibilityLabel("Conservazione")
                .accessibilityHint("Il default segue la categoria; tocca per sovrascrivere")
                DatePicker("Data di scadenza", selection: $expirationDate, displayedComponents: .date)
                QuantityStepper(quantity: $quantity)
            }

            Section {
                Group {
                    if #available(iOS 26.0, *) {
                        Button {
                            Task { await saveItem() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Text("Salva")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.pantryMoss)
                        .disabled(!isFormValid || isSaving)
                    } else {
                        Button {
                            Task { await saveItem() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Text("Salva")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(!isFormValid || isSaving)
                    }
                }
            }
        }
        .navigationTitle("Inserimento manuale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty && !initialName.isEmpty { name = initialName }
            if selectedCategory.isEmpty && !initialCategory.isEmpty { selectedCategory = initialCategory }
        }
        .task(id: name) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                suggestions = try await APIClient.shared.fetchSuggestions(q: trimmed, scope: "pantry")
            } catch {
                suggestions = []
            }
        }
        .alert("Errore", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
        }
    }

    // MARK: - Conservazione (T12)

    /// Stesso pattern di ScanPreviewSheet (T11): finché l'utente non tocca il
    /// picker il valore mostrato è derivato dalla categoria; solo la selezione
    /// utente viene inviata (nil altrimenti → il backend persiste la derivazione).
    private var storageBinding: Binding<String> {
        Binding(
            get: { storageTouched ? selectedStorage : CategoryRegistry.storageLocation(for: selectedCategory) },
            set: { selectedStorage = $0; storageTouched = true }
        )
    }

    private func saveItem() async {
        isSaving = true
        await store.addManual(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            expirationDate: expirationDate,
            category: selectedCategory.nilIfEmpty,
            quantity: quantity,
            storageLocation: storageTouched ? selectedStorage : nil
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
