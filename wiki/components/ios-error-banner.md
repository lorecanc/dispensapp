---
title: "ErrorBanner"
description: "Unified BannerView (error/success, optional auto-dismiss) plus the discrete OfflinePill, driven by ConnectivityMonitor with transport-error to offline classification"
category: "components"
source_files:
  - "ios/Inventario/Components/ErrorBanner.swift"
  - "ios/Inventario/Networking/ConnectivityMonitor.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# ErrorBanner

## Purpose

The banner system (`ios/Inventario/Components/ErrorBanner.swift`) covers two views:

- **`BannerView`**: the single unified banner for transient messages (error and success styles), with optional auto-dismiss. It replaced the pre-unification per-case banners; the Italian VoiceOver kind names (`Errore` / `Successo`) are unchanged.
- **`OfflinePill`**: a discrete non-invasive pill shown when the device is offline — never a red banner.

Offline state is produced by `ConnectivityMonitor` (`ios/Inventario/Networking/ConnectivityMonitor.swift`) and surfaced through `InventoryStore.isOffline`; transport-level failures are classified to `.offline` so they reach the pill instead of the banner.

## Props / Interface

`BannerView`:

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `message` | `String` | yes | The text to display |
| `style` | `Style` (`.error` / `.success`) | yes | Icon, background, and VoiceOver kind words |
| `autoDismiss` | `Bool` | no | When true, calls `onDismiss` after ~4 s with animation (default `false`) |
| `onDismiss` | `(() -> Void)?` | no | Closure called on close-button tap (or auto-dismiss); when nil, the close button is hidden |

`OfflinePill` takes no props — fixed label `Offline — dati non aggiornati`.

## Styles

| Style | Icon | Background | Kind label |
|-------|------|------------|------------|
| `.error` | `exclamationmark.triangle.fill` | `statusExpired` at 90 % | `Errore` / `errore` |
| `.success` | `checkmark.circle.fill` | `statusFresh` at 92 % | `Successo` / `successo` |

Layout is an `HStack(spacing: 8)`: icon (`pantryLinen`), message (`.subheadline`, `pantryLinen`), spacer, conditional `xmark` close button (`.caption` semibold, `pantryLinen` 85 %). Padding is horizontal 16 / vertical 10 inside a `RoundedRectangle(cornerRadius: 10)`, plus outer horizontal padding and top 4. Enter/exit transition is `.move(edge: .top).combined(with: .opacity)`.

## Auto-Dismiss

When `autoDismiss` is true, a `.task(id: message)` sleeps 4 seconds and then calls `onDismiss()` inside `withAnimation(.easeInOut(duration: 0.25))`, matching the removal transition. The task is keyed on `message`, so a new error re-arms the timer and view removal cancels it (`Task.isCancelled` guard).

## Transport-Error → Offline Classification

`InventoryStore` never lets connectivity failures reach the banner. `classify(_:)` remaps `.transport` errors whose `URLError.Code` means "network unreachable" to `APIError.offline`:

`notConnectedToInternet`, `timedOut`, `cannotConnectToHost`, `cannotFindHost`, `networkConnectionLost`, `dataNotAllowed`.

`setError(from:)` — the single setter of `store.error` — drops `.offline` results, so the banner only ever shows genuine errors. Offline display is owned by `store.isOffline` (`!connectivity.isOnline`) rendered as `OfflinePill`. `APIError.offline` reads `Nessuna connessione internet.` for the few paths that surface it directly.

## ConnectivityMonitor

`ConnectivityMonitor` is a minimal `@Observable` / `@MainActor` wrapper over `NWPathMonitor`:

- Publishes `isOnline` (initialised from `monitor.currentPath.status == .satisfied`).
- `start()` attaches `pathUpdateHandler` on a dedicated utility queue and republishes onto the main actor; guarded against double-start. `stop()` detaches the handler and cancels.
- The `NWPathMonitor` instance is injectable (default `NWPathMonitor()`) for tests/previews, and `update(isOnline:)` is a pure seam to drive state without `NWPath`.
- `deinit` cancels the monitor. The store observes `isOnline` via `withObservationTracking` to trigger replay/refresh on reconnect.

## Layout

In [InventoryListView](./ios-inventory-list-view.md) both views share one top overlay (`O2/T13` rule: offline → pill, real errors → self-closing banner; the monitor is already started by `InventoryStore.init`):

```swift
.overlay(alignment: .top) {
    VStack(spacing: 8) {
        if store.isOffline {
            OfflinePill()
                .padding(.top, 8)
        }
        if let error = store.error {
            BannerView(message: error.localizedDescription, style: .error, autoDismiss: true) {
                storeBindable.error = nil
            }
        }
    }
}
```

`OfflinePill` itself is an `HStack(spacing: 6)` (`wifi.slash` + text, `.caption` medium, `textSecondary`) in a `pantryOat` 35 % capsule with a `pantryOat` 0.5 pt stroke.

## Accessibility

- Banner icon is `accessibilityHidden`; the kind label (`"Errore: <message>"` / `"Successo: <message>"`) sits on the `Text`, not the container, so the close button stays actionable to VoiceOver (`.combine` would flatten it).
- Close button label `Chiudi avviso` with a hint naming the kind word.
- Pill is a combined element labelled `Offline, dati non aggiornati`.
- Both views support Dynamic Type `.xSmall ... .accessibility2`.

## Usage

Error banner with auto-dismiss (standard list usage):

```swift
if let error = store.error {
    BannerView(message: error.localizedDescription, style: .error, autoDismiss: true) {
        storeBindable.error = nil
    }
}
```

Persistent message without close button:

```swift
BannerView(message: "Operazione non disponibile", style: .error)
```

Success confirmation:

```swift
BannerView(message: "Prodotto aggiunto", style: .success, autoDismiss: true) {
    showConfirmation = false
}
```

## Related

- [InventoryListView](./ios-inventory-list-view.md) — overlay wiring for pill + banner
- [iOS State Management](../concepts/ios-state-management.md) — `store.error` / `store.isOffline`
