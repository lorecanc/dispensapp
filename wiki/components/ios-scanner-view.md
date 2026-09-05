---
title: "iOS Scanner View"
description: "Continuous multi-scan barcode session for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Scan/ScannerView.swift"
  - "ios/Inventario/Features/Scan/ScanSessionStore.swift"
  - "ios/Inventario/Features/Scan/ScanAcquiredOverlay.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# iOS Scanner View

## Purpose

Provides a continuous multi-scan barcode interface in the Inventario iOS app. Wraps VisionKit's `DataScannerViewController`, accumulates detections in a checkout-style queue (`ScanSessionStore`), confirms each acquisition with a transient ping (`ScanAcquiredOverlay`), and saves all found products to inventory in one batch. The camera never blocks: the preview stays live while lookups resolve in the background.

## VisionKit Integration

`ScannerView` is a `UIViewControllerRepresentable` owned by a `ScanSessionStore`:

```swift
let scanner = DataScannerViewController(
    recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
    qualityLevel: .balanced,
    recognizesMultipleItems: true,
    isHighFrameRateTrackingEnabled: false,
    isHighlightingEnabled: true
)
```

| Parameter | Value | Note |
|-----------|-------|------|
| recognizedDataTypes | `.barcode(symbologies:)` | EAN-13, EAN-8, UPC-E, Code128 |
| qualityLevel | `.balanced` | Balances speed vs accuracy |
| recognizesMultipleItems | `true` | Required for continuous multi-scan |
| isHighFrameRateTrackingEnabled | `false` | Not needed for static barcodes |
| isHighlightingEnabled | `true` | Yellow highlight overlay on detected barcode |

Scanning starts once in `updateUIViewController` via a `hasStartedScanning` flag, and stops in `dismantleUIViewController` via `stopScanning()`. Unlike the original single-shot design, the coordinator never calls `stopScanning()` after a detection.

## Coordinator

`Coordinator` (`NSObject`, `DataScannerViewControllerDelegate`, `@MainActor`) forwards both delegate callbacks to the session:

- **`dataScanner(_:didTapOn:)`** — user taps a highlighted barcode.
- **`dataScanner(_:didAdd:allItems:)`** — barcode detected automatically.

Both extract `payloadStringValue` and call `handleBarcode(_:)`, which enqueues and fetches only on valid enqueue:

```swift
private func handleBarcode(_ code: String) {
    guard let id = session.enqueue(code) else { return }
    self.parent.onBarcodeScanned?(code)
    Task { await session.fetch(id: id) }
}
```

Debounced or duplicate detections return `nil` from `enqueue` and stay silent — no ping, no banner, no fetch.

## ScanSessionStore

`ScanSessionStore` (`@Observable`, `@MainActor`) is the single source of truth for the scan session.

### Queue Model

```swift
enum ScanItemState: String, Sendable {
    case pending, loading, found, notFound, error
}

struct ScanQueueItem: Identifiable, Sendable {
    let id: UUID
    let barcode: String
    var state: ScanItemState
    var result: ScanResult?
    var errorMessage: String?
    let createdAt: Date
}
```

### Debounced Enqueue

`enqueue(_:) -> UUID?` discards `nil`/empty input, then applies two guards:

1. **Per-barcode cooldown** (`cooldown = 1.5`s): the same barcode inside the window is skipped; different barcodes pass immediately.
2. **In-flight guard**: a barcode already `.pending`/`.loading` in the queue is skipped.

Eviction keeps `maxQueueSize = 20`: finished items (`.found`/`.notFound`/`.error`) are dropped first, otherwise the oldest item is removed. Returns the new item's `UUID`, or `nil` when skipped.

### Fetch / Retry / Mutations

| Method | Behavior |
|--------|----------|
| `enqueueAndFetch(_:)` | Convenience: enqueue then fetch (used by previews/tests) |
| `fetch(id:)` | Sets `.loading`, calls `APIClient.scan(barcode:)` (see [Scan API](../api/scan.md); or injected `fetcher` in tests), maps `result.found` to `.found`/`.notFound`, maps `APIError.notFound` to `.notFound` and other errors to `.error` with message |
| `retry(id:)` | Resets to `.pending` and re-fetches (used by row retry button) |
| `updateState(id:to:result:errorMessage:)` | Patches state/result/message for one row |
| `delete(id:)` | Removes one row |
| `clearSaved()` | Drops `.found` rows after a batch save; error rows stay editable |
| `clear()` | Empties queue and resets debounce map (used by "Termina") |

The `fetcher` closure (`(@Sendable (String) async throws -> ScanResult)?`) is test-only dependency injection; production always uses `APIClient.shared`.

## ScanAcquiredOverlay

Transient "checkout ping" shown after each valid enqueue. Two types:

### ScanAcquiredController

`@Observable` `@MainActor` controller holding an optional `Pill` (`id` + `barcode`):

- **`show(barcode:) -> Bool`** — fires `UINotificationFeedbackGenerator.success` haptic and VoiceOver announcement *before* any await (<300ms feedback), sets the pill with a spring animation, and schedules auto-dismiss after `visibleDuration = 0.9`s. Throttles announcements to `announcementCooldown = 1.5`s (matches session cooldown). Ignores empty input.
- **`dismiss()`** — cancels the timer and fades the pill (600ms ease-out, or 200ms linear with Reduce Motion).

### ScanAcquiredOverlay

Centered glass card (`pantryGlassChrome()`) with a 64pt `checkmark.circle.fill`, "Acquisito" headline, and monospaced barcode. Scale+opacity entrance, combined scale/opacity transition on exit, `dynamicTypeSize(.xSmall ... .accessibility2)`. Glass lives only on the container; inner content uses plain Terra tokens.

## ScannerViewWrapper Layout

`ScannerViewWrapper` owns the session (`@State ScanSessionStore`), the ping controller (`@State ScanAcquiredController`), the on-demand editor (`editingItem`), transient banners, and save state. Three layers in a `ZStack`:

1. **Camera (fullscreen, never blocked)** — `ScannerView(session:)` with `.ignoresSafeArea()`. `onBarcodeScanned` fires `acquired.show(barcode:)` plus a success banner `"Acquisito <code> in coda (<n>)"`.
2. **Top banner (auto-dismiss 2s)** — `BannerView` success/error, one at a time, cancelled on disappear.
3. **Bottom queue panel** — shown only when the queue is non-empty; `ScrollView` + `LazyVStack` capped at 220pt, `pantryGlassChrome()` container, `dynamicTypeSize(.xSmall ... .accessibility2)`.

Chrome: top-trailing close button (Liquid Glass `glassEffect` on iOS 26+, `ultraThinMaterial` fallback), `navigationTitle("Scansiona")` inline, leading "Chiudi" toolbar item, `.sheet(item: $editingItem)` opening `ScanPreviewSheet` on-demand per row tap (never auto-presented), and the camera-permission alert (`NSCameraUsageDescription`: "Per scansionare i codici a barre dei prodotti."). When VisionKit is unsupported/unavailable, a `ContentUnavailableView` ("Scanner non disponibile") is shown instead.

### ScanQueueRow

One row per `ScanQueueItem`: state icon (clock / magnifyingglass / checkmark / magnifyingglass-exclamation / warning triangle), 40pt product thumbnail (only when `.found` with image URL), name-or-barcode headline, monospaced status line (`"In coda ·"`, `"Ricerca… ·"`, barcode, `"Non trovato ·"`, error message), `×1` capsule, `ProgressView` while pending/loading, retry button (`.error`/`.notFound` only), delete button + destructive context menu. Full-row tap opens the editor.

### Batch Save

`"Rivedi e salva (<foundCount>)"` (`.borderedProminent`, `pantryMoss`, disabled when zero found or saving) runs `saveAll()`:

1. For each `.found` item, calls `InventoryStore.add(...)` sequentially (category validated against `CategoryRegistry.validCategoryKeys`, quantity 1).
2. Save failures flip that row to `.error` with the store message instead of aborting the batch.
3. `session.clearSaved()` drops saved rows; error/not-found rows remain for review.
4. Banner summarizes: `"Salvati N prodotti"`, `"Salvati N, M da rivedere"`, or `"M da rivedere: tocca la riga per correggere"`.

`"Termina"` clears the session and dismisses.

## Fixes

- **Orientations**: supported interface orientations corrected so the camera preview and overlay layers rotate correctly on device.
- **Project membership**: Xcode `pbxproj` target membership fixed so the new Scan files (`ScanSessionStore`, `ScanAcquiredOverlay`) compile into the app target.

## Key Files

| File | Role |
|------|------|
| `ios/Inventario/Features/Scan/ScannerView.swift` | `ScannerView`, `Coordinator`, `ScannerViewWrapper`, `ScanQueueRow`, batch save |
| `ios/Inventario/Features/Scan/ScanSessionStore.swift` | `ScanSessionStore`, `ScanQueueItem`, `ScanItemState`, debounced queue + fetch |
| `ios/Inventario/Features/Scan/ScanAcquiredOverlay.swift` | `ScanAcquiredController`, `ScanAcquiredOverlay` transient ping |
