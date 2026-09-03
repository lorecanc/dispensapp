import SwiftUI
import VisionKit

struct ScannerView: UIViewControllerRepresentable {
    let session: ScanSessionStore
    var onBarcodeScanned: ((String) -> Void)?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !context.coordinator.hasStartedScanning {
            context.coordinator.hasStartedScanning = true
            try? uiViewController.startScanning()
        }
    }

    func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, session: session)
    }

    @MainActor
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ScannerView
        let session: ScanSessionStore
        var hasStartedScanning = false

        init(parent: ScannerView, session: ScanSessionStore) {
            self.parent = parent
            self.session = session
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                        didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let barcode):
                guard let code = barcode.payloadStringValue, !code.isEmpty else { return }
                print("[Scanner] Barcode detected:", code)
                handleBarcode(code)
            default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                        didAdd addedItems: [RecognizedItem],
                        allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let barcode):
                    guard let code = barcode.payloadStringValue, !code.isEmpty else { continue }
                    print("[Scanner] Barcode detected:", code)
                    handleBarcode(code)
                default:
                    break
                }
            }
        }

        // Valid enqueue only: debounced/duplicates return nil and stay silent.
        private func handleBarcode(_ code: String) {
            guard let id = session.enqueue(code) else { return }
            self.parent.onBarcodeScanned?(code)
            Task { await session.fetch(id: id) }
        }
    }
}

// MARK: - SwiftUI wrapper with permission handling

struct ScannerViewWrapper: View {
    @Environment(InventoryStore.self) private var inventory
    @Environment(\.dismiss) private var dismiss
    @State private var session = ScanSessionStore()
    @State private var acquired = ScanAcquiredController()
    @State private var editingItem: ScanQueueItem?
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var isSavingAll = false
    @State private var showPermissionAlert = false
    @State private var bannerTask: Task<Void, Never>?

    private var foundCount: Int {
        session.queue.filter { $0.state == .found }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ZStack {
                        // Layer 1: camera fullscreen, mai bloccata.
                        ScannerView(session: session) { barcode in
                            onValidEnqueue(barcode)
                        }
                        .ignoresSafeArea()

                        // Layer 2: banner top auto-dismiss 2s.
                        VStack(spacing: 0) {
                            if let successMessage {
                                SuccessBanner(message: successMessage) {
                                    self.successMessage = nil
                                }
                            } else if let errorMessage {
                                ErrorBanner(message: errorMessage) {
                                    self.errorMessage = nil
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .animation(.easeInOut(duration: 0.25), value: successMessage)
                        .animation(.easeInOut(duration: 0.25), value: errorMessage)

                        // Ping centrale transitorio dopo enqueue valido.
                        if let pill = acquired.pill {
                            ScanAcquiredOverlay(barcode: pill.barcode)
                                .id(pill.id)
                        }

                        // Layer 3: coda bottom, altezza limitata e scrollabile.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if !session.queue.isEmpty {
                                scanQueuePanel
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Group {
                            if #available(iOS 26.0, *) {
                                GlassEffectContainer {
                                    Button {
                                        dismiss()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                            .shadow(radius: 2)
                                            .padding(8)
                                            .accessibilityHidden(true)
                                    }
                                    .glassEffect(.regular, in: Circle())
                                    .accessibilityLabel("Chiudi scanner")
                                    .accessibilityHint("Chiude la fotocamera e torna alla dispensa")
                                }
                            } else {
                                Button {
                                    dismiss()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.4))
                                        .accessibilityHidden(true)
                                }
                                .background(.ultraThinMaterial, in: Circle())
                                .accessibilityLabel("Chiudi scanner")
                                .accessibilityHint("Chiude la fotocamera e torna alla dispensa")
                            }
                        }
                        .padding()
                    }
                    .accessibilityElement(children: .contain)
                } else {
                    ContentUnavailableView(
                        "Scanner non disponibile",
                        systemImage: "barcode.viewfinder",
                        description: Text("Il dispositivo non supporta la scansione di codici a barre.")
                    )
                    .accessibilityLabel("Scanner non disponibile")
                    .accessibilityHint("Il dispositivo non supporta la scansione codici a barre")
                    .dynamicTypeSize(.xSmall ... .accessibility3)
                }
            }
            .navigationTitle("Scansiona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .accessibilityLabel("Chiudi scanner")
                        .accessibilityHint("Chiude la fotocamera")
                }
            }
            // Editor solo on-demand dal tap sulla riga, mai auto-bloccante.
            .sheet(item: $editingItem) { item in
                ScanPreviewSheet(barcode: item.barcode, result: item.result)
            }
            .alert("Accesso alla fotocamera", isPresented: $showPermissionAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Per scansionare i codici a barre è necessario concedere l'accesso alla fotocamera.")
            }
        }
    }

    // MARK: - Enqueue feedback

    private func onValidEnqueue(_ barcode: String) {
        acquired.show(barcode: barcode)
        showTransientSuccess("Acquisito \(barcode) in coda (\(session.queue.count))")
    }

    private func showTransientSuccess(_ message: String) {
        errorMessage = nil
        successMessage = message
        restartBannerTimer()
    }

    private func showTransientError(_ message: String) {
        successMessage = nil
        errorMessage = message
        restartBannerTimer()
    }

    private func restartBannerTimer() {
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            successMessage = nil
            errorMessage = nil
        }
    }

    // MARK: - Bottom queue (unico Glass consentito: ScannerOverlay)

    private var scanQueuePanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(session.queue) { item in
                        ScanQueueRow(
                            item: item,
                            onTap: { editingItem = item },
                            onDelete: { session.delete(id: item.id) },
                            onRetry: { Task { await session.retry(id: item.id) } }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 220)
            .scrollIndicators(.hidden)

            HStack(spacing: 12) {
                Button("Rivedi e salva (\(foundCount))") {
                    Task { await saveAll() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pantryMoss)
                .disabled(foundCount == 0 || isSavingAll)
                .accessibilityLabel("Rivedi e salva \(foundCount) prodotti")
                .accessibilityHint("Salva tutti i prodotti trovati nella dispensa")

                Spacer(minLength: 0)

                Button("Termina") {
                    session.clear()
                    dismiss()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Termina sessione")
                .accessibilityHint("Svuota la coda e chiude lo scanner")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .pantryGlassChrome()
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    // Salva tutti i trovati via InventoryStore.add in sequenza:
    // raccoglie i fallimenti senza abortire, le righe errate restano editabili.
    private func saveAll() async {
        isSavingAll = true
        defer { isSavingAll = false }
        var saved = 0
        var toReview = session.queue.filter { $0.state == .notFound || $0.state == .error }.count
        for item in session.queue where item.state == .found {
            guard let result = item.result else {
                toReview += 1
                continue
            }
            let rawCategory = result.categories.first ?? ""
            await inventory.add(
                barcode: item.barcode,
                name: result.name ?? item.barcode,
                brand: result.brand,
                expirationDate: nil,
                category: CategoryRegistry.validCategoryKeys.contains(rawCategory) ? rawCategory : nil,
                imageURL: result.imageURL,
                quantity: 1
            )
            if inventory.error == nil {
                saved += 1
            } else {
                let message = inventory.error?.localizedDescription ?? "Salvataggio non riuscito"
                session.updateState(id: item.id, to: .error, result: result, errorMessage: message)
                toReview += 1
            }
        }
        session.clearSaved()
        if saved > 0, toReview == 0 {
            showTransientSuccess("Salvati \(saved) prodotti")
        } else if saved > 0 {
            showTransientError("Salvati \(saved), \(toReview) da rivedere")
        } else if toReview > 0 {
            showTransientError("\(toReview) da rivedere: tocca la riga per correggere")
        }
    }
}

// MARK: - Queue row

private struct ScanQueueRow: View {
    let item: ScanQueueItem
    var onTap: () -> Void
    var onDelete: () -> Void
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                stateIcon
                if let url = thumbURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.pantryOat.opacity(0.35)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.result?.name ?? item.barcode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if item.state == .loading || item.state == .pending {
                    ProgressView()
                        .tint(Color.pantryMoss)
                        .accessibilityLabel("Ricerca prodotto in corso")
                }
                Text("×1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.pantryOat.opacity(0.35), in: Capsule())
                    .accessibilityLabel("Quantità 1")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.result?.name ?? "Codice") \(item.barcode), \(statusText)")
            .accessibilityHint("Tocca per rivedere e salvare")
            .accessibilityAddTraits(.isButton)
            if item.state == .error || item.state == .notFound {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.pantryMoss)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Riprova ricerca")
                .accessibilityHint("Riprova la ricerca del prodotto \(item.barcode)")
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.statusExpired)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Elimina \(item.barcode) dalla coda")
            .accessibilityHint("Rimuove il codice dalla coda di scansione")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .pantryCardBackground(cornerRadius: 12)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Elimina", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(Color.textSecondary)
        case .loading:
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.pantryMoss)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.statusFresh)
        case .notFound:
            Image(systemName: "exclamationmark.magnifyingglass")
                .foregroundStyle(Color.statusSoon)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusExpired)
        }
    }

    private var thumbURL: URL? {
        guard item.state == .found,
              let raw = item.result?.imageURL,
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    private var statusText: String {
        switch item.state {
        case .pending: return "In coda · \(item.barcode)"
        case .loading: return "Ricerca… · \(item.barcode)"
        case .found: return item.barcode
        case .notFound: return "Non trovato · \(item.barcode)"
        case .error: return item.errorMessage ?? "Errore · \(item.barcode)"
        }
    }
}
