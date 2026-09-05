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

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Dettagli prodotto") {
                TextField("Nome *", text: $name)
                    .autocorrectionDisabled()

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
