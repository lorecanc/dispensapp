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
                DatePicker("Data di scadenza", selection: $expirationDate, displayedComponents: .date)
                QuantityStepper(quantity: $quantity)
            }

            Section {
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

    private func saveItem() async {
        isSaving = true
        await store.addManual(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            expirationDate: expirationDate,
            category: selectedCategory.nilIfEmpty,
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
