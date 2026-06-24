---
title: "ErrorBanner"
description: "Dismissable red error banner displayed at the top of the inventory list on error conditions"
category: "components"
source_files:
  - "ios/Inventario/Components/ErrorBanner.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# ErrorBanner

## Purpose

A transient notification banner that presents error messages to the user with an optional dismiss action. Rendered as an overlay on the inventory list to surface non-blocking errors.

## Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `message` | `String` | yes | The error text to display |
| `onDismiss` | `(() -> Void)?` | no | Closure called when the user taps the close button; if nil, the close button is hidden |

## Layout

The banner uses an `HStack` with the following structure:

1. **Icon**: `exclamationmark.triangle.fill` in white
2. **Message**: `Text` in `.subheadline` font, white foreground
3. **Spacer**: pushes content to the edges
4. **Dismiss button** (conditional): `xmark` icon in white at 80% opacity, `.caption.weight(.semibold)` font. Only rendered when `onDismiss` is non-nil.

## Appearance

| Property | Value |
|----------|-------|
| Background | `.red.opacity(0.85)` |
| Clip shape | `RoundedRectangle(cornerRadius: 10)` |
| Inner padding | horizontal 16, vertical 10 |
| Outer padding | horizontal (via `.padding(.horizontal)`), top 4 |

## Transition Animation

```swift
.transition(.move(edge: .top).combined(with: .opacity))
```

The banner slides in from the top edge while fading, and reverses on removal.

## Usage

```swift
if let errorMessage = viewModel.errorMessage {
    ErrorBanner(message: errorMessage) {
        viewModel.dismissError()
    }
}
```

Without dismiss button (persistent message):

```swift
ErrorBanner(message: "Operazione non disponibile")
```

## Usage Location

- **[InventoryListView](../components/ios-inventory-list-view.md)** — rendered as an overlay when an [error state](../concepts/ios-state-management.md) is active in the store.

## Notes

- The banner is not a sheet or alert — it overlays inline within the view hierarchy.
- The `.padding(.horizontal)` before `.padding(.top, 4)` creates a slight horizontal inset effect around the rounded rectangle.
