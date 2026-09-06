import PhotosUI
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
    @State private var selectedStorage: String = "dispensa"
    @State private var storageTouched = false
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
    @State private var contributeLabels = ""
    @State private var contributeGenericName = ""
    @State private var contributeComment = ""
    @State private var consentCCBYSA = false
    @State private var contributeLoading = false
    @State private var contributeSuccessMessage: String?
    @State private var contributeError: APIError?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoFilename = "foto.jpg"
    @State private var photoMimeType = "image/jpeg"
    @State private var selectedImageField = "front_it"
    @State private var photoLoading = false
    @State private var photoSuccessMessage: String?
    @State private var photoError: APIError?

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

                if let source = result.sourceEnum {
                    HStack {
                        Text("Sorgente")
                        Spacer()
                        sourceBadge(source)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Sorgente: \(source.displayName)")
                }

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

            if result.needsEnrichment {
                contributeSection(barcode: barcode)
            }
        }
    }

    /// Badge sorgente non tappabile, stesso stile dei chip categoria
    /// (Capsule + thinMaterial + pantryLinen/pantryOat). Il label per
    /// VoiceOver sta sulla riga chiamante ("Sorgente: ...").
    private func sourceBadge(_ source: ProductSource) -> some View {
        Text(source.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(Capsule().fill(Color.pantryLinen.opacity(0.45)))
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.pantryOat, lineWidth: 0.5)
            )
            .accessibilityHidden(true)
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
                TextField("Etichette (separate da virgola)", text: $contributeLabels, axis: .vertical)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Etichette da contribuire")
                TextField("Nome generico", text: $contributeGenericName)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Nome generico da contribuire")
                TextField("Commento", text: $contributeComment, axis: .vertical)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Commento da contribuire")
                Toggle(isOn: $consentCCBYSA) {
                    Text("Acconsento alla pubblicazione di dati e foto con licenza CC BY-SA / ODbL su Open Food Facts, con cessione irrevocabile delle foto come da termini OFF. Obbligatorio per inviare.")
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

                Divider()

                Text("Foto prodotto")
                    .font(.headline)
                    .accessibilityLabel("Foto prodotto")
                Text("Aggiungi una foto (max 5MB, JPEG/PNG/HEIC): sarà pubblicata con licenza aperta CC BY-SA / ODbL con cessione irrevocabile come da termini OFF.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(photoData == nil ? "Scegli una foto" : "Cambia foto", systemImage: "photo")
                }
                .accessibilityLabel("Scegli una foto del prodotto")
                .accessibilityHint("Apre la libreria foto")
                .onChange(of: selectedPhotoItem) {
                    Task { await loadSelectedPhoto(code: barcode) }
                }
                if photoData != nil {
                    Text(photoFilename)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityLabel("Foto selezionata \(photoFilename)")
                }
                Picker("Tipo di foto", selection: $selectedImageField) {
                    Text("Fronte").tag("front_it")
                    Text("Ingredienti").tag("ingredients_it")
                    Text("Valori nutrizionali").tag("nutrition_it")
                    Text("Confezione").tag("packaging_it")
                }
                .accessibilityLabel("Tipo di foto")
                .accessibilityHint("Scegli quale vista del prodotto mostra la foto")

                if photoLoading {
                    ProgressView("Invio foto in corso...")
                        .accessibilityLabel("Invio foto in corso")
                } else if let message = photoSuccessMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                        .accessibilityLabel("Foto inviata: \(message)")
                } else {
                    if let photoError {
                        Text(photoError.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Errore foto: \(photoError.localizedDescription)")
                    }
                    Button(photoError == nil ? "Invia foto" : "Riprova") {
                        Task { await sendPhoto(code: barcode) }
                    }
                    .disabled(!consentCCBYSA || photoLoading || photoData == nil)
                    .accessibilityHint("Disponibile solo dopo aver dato il consenso e scelto una foto")
                    if photoData == nil {
                        Text("Scegli una foto per continuare")
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
        photoSuccessMessage = nil
        photoError = nil
    }

    private var isContributeEmpty: Bool {
        [contributeName, contributeBrands, contributeQuantity, contributeCategories, contributeLabels, contributeGenericName].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// app_uuid stabile per installazione, riusando UserDefaults (come APIConfig)
    /// senza nuove dipendenze: generato una volta e riusato per ogni contribute().
    private static func persistedAppUUID() -> String {
        let key = "contributeAppUUID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
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
                labels: contributeLabels.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                genericName: contributeGenericName.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                comment: contributeComment.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                appUUID: Self.persistedAppUUID(),
                consent: consentCCBYSA
            )
            contributeSuccessMessage = response.message ?? "Contributo inviato, grazie!"
        } catch {
            contributeError = error as? APIError ?? .transport(error)
        }
        contributeLoading = false
    }

    private func loadSelectedPhoto(code: String) async {
        guard let item = selectedPhotoItem else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                photoData = nil
                photoError = .transport(URLError(.cannotDecodeContentData, userInfo: [NSLocalizedDescriptionKey: "Impossibile leggere la foto selezionata."]))
                return
            }
            photoData = data
            let (filename, mimeType) = Self.photoFilenameAndMime(data: data, code: code, imagefield: selectedImageField)
            photoFilename = filename
            photoMimeType = mimeType
            photoSuccessMessage = nil
            photoError = nil
        } catch {
            photoData = nil
            photoError = .transport(error)
        }
    }

    private func sendPhoto(code: String) async {
        guard let data = photoData else { return }
        // Ricalcola filename/mime dal contenuto: selectedImageField potrebbe
        // essere cambiato dopo la scelta della foto (filename stale).
        let (filename, mimeType) = Self.photoFilenameAndMime(data: data, code: code, imagefield: selectedImageField)
        photoFilename = filename
        photoMimeType = mimeType
        photoLoading = true
        photoError = nil
        photoSuccessMessage = nil
        do {
            let response = try await store.client.uploadPhoto(
                code: code,
                imageData: data,
                filename: filename,
                mimeType: mimeType,
                imagefield: selectedImageField,
                consent: consentCCBYSA
            )
            photoSuccessMessage = response.message ?? "Foto inviata, grazie!"
        } catch {
            photoError = error as? APIError ?? .transport(error)
        }
        photoLoading = false
    }

    static let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
    static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func photoFilenameAndMime(data: Data, code: String, imagefield: String) -> (String, String) {
        if data.starts(with: jpegMagic) {
            return ("\(code)_\(imagefield).jpg", "image/jpeg")
        }
        if data.starts(with: pngMagic) {
            return ("\(code)_\(imagefield).png", "image/png")
        }
        return ("\(code)_\(imagefield).heic", "image/heic")
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
        // T11: la categoria suggerita dal backend (se valida) vince sul vecchio
        // fallback (primo tag OFF con chiave valida); backend datati → nil.
        let validKeys = CategoryRegistry.validCategoryKeys
        let suggested = result.suggestedCategory.flatMap { validKeys.contains($0) ? $0 : nil }
        let rawCategory = suggested ?? result.categories.first ?? ""
        selectedCategory = validKeys.contains(rawCategory) ? rawCategory : ""
        selectedStorage = CategoryRegistry.storageLocation(for: selectedCategory)
        storageTouched = false
    }

    // MARK: - Conservazione (T11)

    /// Finché l'utente non tocca il picker il valore mostrato è derivato dalla
    /// categoria; solo la selezione utente segna `storageTouched` (e viene inviata,
    /// nil altrimenti → il backend persiste la derivazione).
    private var storageBinding: Binding<String> {
        Binding(
            get: { storageTouched ? selectedStorage : CategoryRegistry.storageLocation(for: selectedCategory) },
            set: { selectedStorage = $0; storageTouched = true }
        )
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
            quantity: quantity,
            offTags: scanResult?.categories,
            storageLocation: storageTouched ? selectedStorage : nil,
            source: scanResult?.source,
            productType: scanResult?.productType
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
