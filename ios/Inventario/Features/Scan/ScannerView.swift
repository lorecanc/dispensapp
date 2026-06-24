import SwiftUI
import VisionKit

struct ScannerView: UIViewControllerRepresentable {
    var onBarcodeScanned: ((String) -> Void)?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ScannerView
        var hasStartedScanning = false
        var hasScanned = false

        init(parent: ScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                        didTapOn item: RecognizedItem) {
            guard !hasScanned else { return }
            switch item {
            case .barcode(let barcode):
                hasScanned = true
                let payload = barcode.payloadStringValue ?? ""
                print("[Scanner] Barcode detected:", payload)
                DispatchQueue.main.async {
                    dataScanner.stopScanning()
                    self.parent.onBarcodeScanned?(payload)
                }
            default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                        didAdd addedItems: [RecognizedItem],
                        allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            guard let item = addedItems.first else { return }
            switch item {
            case .barcode(let barcode):
                hasScanned = true
                let payload = barcode.payloadStringValue ?? ""
                print("[Scanner] Barcode detected:", payload)
                DispatchQueue.main.async {
                    dataScanner.stopScanning()
                    self.parent.onBarcodeScanned?(payload)
                }
            default:
                break
            }
        }
    }
}

// MARK: - Identifiable barcode wrapper

struct ScannedBarcode: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - SwiftUI wrapper with permission handling

struct ScannerViewWrapper: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedBarcode: ScannedBarcode?
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView { barcode in
                        scannedBarcode = ScannedBarcode(value: barcode)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.4))
                                .padding()
                        }
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanner non disponibile",
                        systemImage: "barcode.viewfinder",
                        description: Text("Il dispositivo non supporta la scansione di codici a barre.")
                    )
                }
            }
            .navigationTitle("Scansiona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(item: $scannedBarcode) { barcode in
                ScanPreviewSheet(barcode: barcode.value)
            }
            .alert("Accesso alla fotocamera", isPresented: $showPermissionAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Per scansionare i codici a barre è necessario concedere l'accesso alla fotocamera.")
            }
        }
    }
}
