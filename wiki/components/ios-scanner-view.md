---
title: "iOS Scanner View"
description: "VisionKit barcode scanner component for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Scan/ScannerView.swift"
  - "ios/Inventario/Features/Scan/ScanPreviewSheet.swift"
  - "ios/Inventario/Info.plist"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS Scanner View

## Purpose

Provides a native barcode scanning interface in the Inventario iOS app by wrapping `DataScannerViewController` from VisionKit. Detects EAN/UPC/Code128 barcodes, presents a preview sheet with the scanned result (looked up via Open Food Facts), and allows the user to save the product to inventory.

## VisionKit Integration

`ScannerView` is a `UIViewControllerRepresentable` that wraps `DataScannerViewController`:

```swift
let scanner = DataScannerViewController(
    recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
    qualityLevel: .balanced,
    recognizesMultipleItems: false,
    isHighFrameRateTrackingEnabled: false,
    isHighlightingEnabled: true
)
```

| Parameter | Value | Note |
|-----------|-------|------|
| recognizedDataTypes | `.barcode(symbologies:)` | EAN-13, EAN-8, UPC-E, Code128 |
| qualityLevel | `.balanced` | Balances speed vs accuracy |
| recognizesMultipleItems | `false` | Single barcode at a time |
| isHighFrameRateTrackingEnabled | `false` | Not needed for static barcodes |
| isHighlightingEnabled | `true` | Yellow highlight overlay on detected barcode |

Scanning starts once in `updateUIViewController` via a `hasStartedScanning` flag, ensuring `startScanning()` is called only once.

## Coordinator Delegate Pattern

The `Coordinator` (`NSObject`, `DataScannerViewControllerDelegate`) prevents duplicate scans with a `hasScanned` flag:

- **`dataScanner(_:didTapOn:)`** — called when the user taps a recognized barcode.
- **`dataScanner(_:didAdd:allItems:)`** — called when a barcode is automatically detected.

Both methods:
1. Guard against `hasScanned` (no duplicates).
2. Extract `payloadStringValue` from the recognised barcode.
3. Set `hasScanned = true`.
4. Call `stopScanning()` on the scanner.
5. Invoke the `onBarcodeScanned` closure on the main queue.

## ScannedBarcode

A simple `Identifiable` wrapper used to present the scan result sheet:

```swift
struct ScannedBarcode: Identifiable {
    let id = UUID()
    let value: String
}
```

## SwiftUI Wrapper and Permission Handling

`ScannerViewWrapper` is the SwiftUI entry point that handles three states:

### Scanner available (`isSupported && isAvailable`)

Shows `ScannerView` with an overlay close button (top-trailing `xmark.circle.fill`) and a toolbar "Chiudi" button. The view ignores safe areas for full-screen scanning.

### Scanner unavailable (`!isSupported || !isAvailable`)

Shows a `ContentUnavailableView` with:
- Title: "Scanner non disponibile"
- Icon: `barcode.viewfinder`
- Description: "Il dispositivo non supporta la scansione di codici a barre."

### Camera permission alert

An `.alert` with title "Accesso alla fotocamera" and message "Per scansionare i codici a barre è necessario concedere l'accesso alla fotocamera." Tapping OK dismisses the view.

The permission prompt is triggered automatically by VisionKit when `startScanning()` is called. The `NSCameraUsageDescription` in [Info.plist](../config/ios-config.md) provides the system prompt text:

```
Per scansionare i codici a barre dei prodotti.
```

## Scan Flow

1. User opens `ScannerViewWrapper`.
2. Camera feed appears; the viewfinder highlights detected barcodes.
3. On barcode detection (tap or automatic), scanning stops.
4. A `ScannedBarcode` is set, presenting [ScanPreviewSheet](../components/ios-scan-preview-sheet.md) as a `.sheet(item:)`.
5. `ScanPreviewSheet` calls [APIClient.scan(barcode:)](../concepts/ios-networking.md) to look up the product on Open Food Facts.
6. The sheet shows a form with pre-filled data (name, brand, category) from the lookup, or a "Prodotto non trovato" message if the barcode is unknown.
7. User edits fields and taps "Salva" to persist via `InventoryStore.add(...)`.
8. On success, the sheet and scanner dismiss. On error, an alert is shown.

## Key Files

| File | Role |
|------|------|
| `ios/Inventario/Features/Scan/ScannerView.swift` | `ScannerView`, `Coordinator`, `ScannedBarcode`, `ScannerViewWrapper` |
| `ios/Inventario/Features/Scan/ScanPreviewSheet.swift` | Scan result preview form with local store save |
| `ios/Inventario/Info.plist` | `NSCameraUsageDescription` for camera permission prompt |
