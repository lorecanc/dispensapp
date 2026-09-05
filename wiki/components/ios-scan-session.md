---
title: "iOS Scan Session"
description: "Continuous-scan queue, acquired pill overlay, and VisionKit scanner wrapper for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Scan/ScanSessionStore.swift"
  - "ios/Inventario/Features/Scan/ScanAcquiredOverlay.swift"
  - "ios/Inventario/Features/Scan/ScannerView.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# iOS Scan Session

## Purpose

Continuous-scan stack for checkout-style barcode capture: `ScanSessionStore` owns a debounced fetch queue, `ScanAcquiredOverlay` + `ScanAcquiredController` give immediate per-enqueue feedback, and `ScannerView` / `ScannerViewWrapper` wire VisionKit `DataScannerViewController` to the queue with a bottom panel and save-all flow.

## Props / Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `ScanSessionStore.queue` | `[ScanQueueItem]` | yes | Central queue; each item carries `id`, `barcode`, `state`, `result`, `errorMessage`, `createdAt` |
| `ScanItemState` | `pending / loading / found / notFound / error` | yes | Lifecycle of a `ScanQueueItem` |
| `ScanSessionStore.cooldown` | `TimeInterval` (1.5s) | no | Per-barcode debounce window; duplicates inside it are dropped |
| `ScanSessionStore.maxQueueSize` | `Int` (20) | no | Cap; finished items evicted first, otherwise oldest |
| `ScanAcquiredController.pill` | `Pill?` (`id` + `barcode`) | no | Transient overlay model; auto-dismisses after `visibleDuration` (0.9s) + 600ms fade |
| `ScannerView.session` | `ScanSessionStore` | yes | Shared store passed to the `Coordinator` for enqueue/fetch |
| `ScannerView.onBarcodeScanned` | `((String) -> Void)?` | no | Callback fired only on valid (non-debounced) enqueue |

## Usage

Camera layer stays fullscreen and never blocks; enqueue path is `enqueue` → fetch, with the overlay shown only on valid enqueue:

```swift
@State private var session = ScanSessionStore()
@State private var acquired = ScanAcquiredController()

ScannerView(session: session) { barcode in
    acquired.show(barcode: barcode)
}
.overlay {
    if let pill = acquired.pill {
        ScanAcquiredOverlay(barcode: pill.barcode).id(pill.id)
    }
}
```

Key APIs on `ScanSessionStore` (`@Observable`, `@MainActor`, injectable `APIClient` or `fetcher` for tests):

- `enqueue(_:)` — trims input, drops nil/empty, skips same barcode inside cooldown or already pending/loading, evicts to `maxQueueSize`, appends `.pending` item; returns `UUID?`.
- `enqueueAndFetch(_:)` — main entry: `enqueue` then `fetch(id:)` off-main via `APIClient.scan`.
- `fetch(id:)` — sets `.loading`, maps `found == true` to `.found`, `false` / `.notFound` error to `.notFound`, other errors to `.error` with message.
- `retry(id:)` — resets to `.pending` and re-fetches; error/notFound rows expose a retry button.
- `clearSaved()` — drops `.found` items after the caller saves them via `InventoryStore.add`; `clear()` drops everything plus debounce state; `delete(id:)` removes one row.

## Acquired Feedback

`ScanAcquiredController.show(barcode:)` returns `Bool` (false on empty input) and must run with no awaits before feedback: success haptic (`UINotificationFeedbackGenerator`), spring show of the pill (linear 0.2s under Reduce Motion), and a throttled VoiceOver announce (`announcementCooldown` 1.5s, matching store cooldown):

```swift
UIAccessibility.post(notification: .announcement, argument: "Codice acquisito \(code)")
```

`ScanAcquiredOverlay(barcode:)` renders the centered pill: 64pt `checkmark.circle.fill`, "Acquisito" headline, monospaced barcode caption, `pantryGlassChrome()` container, opacity+scale transition, combined accessibility label "Codice acquisito \<barcode\>", Dynamic Type `.xSmall ... .accessibility2`.

## Related

- [iOS Scan Preview Sheet](./ios-scan-preview-sheet.md)
- [iOS Scanner View](./ios-scanner-view.md)
