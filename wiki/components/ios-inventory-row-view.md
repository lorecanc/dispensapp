---
title: "InventoryRowView"
description: "Card-style list row for a single inventory item — CachedThumbnail image, name/brand/category chip, status badge (hidden when ok), and quantity capsule"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/InventoryRowView.swift"
  - "ios/Inventario/Components/CachedThumbnail.swift"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# InventoryRowView

## Purpose

`InventoryRowView` renders a single inventory item inside the grouped list in [InventoryListView](./ios-inventory-list-view.md). It takes an `InventoryItem` and lays it out as a liquid-glass card: thumbnail, name/brand/category on the left, status badge plus quantity on the right.

## Props / Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `item` | `InventoryItem` | yes | Name, optional brand/category, `imageURL` string, `quantity`, raw `status` string, optional `expirationDate` (used for the VoiceOver label) |

The view takes no bindings or callbacks. Tap handling (detail sheet), swipe actions (consume/delete), and list insets live in the parent `InventoryListView`.

## Layout

The top-level container is an `HStack(spacing: 12)` with `.padding(12)`, rendered as a card rather than a plain row:

```
[HStack]
  [CachedThumbnail 56×56]  [VStack (name, brand?, category chip?)]  [Spacer]  [VStack (StatusBadge?, ×N)]
```

- **Left**: `CachedThumbnail` (56 pt square, corner radius 12).
- **Center-left**: name (headline, `textPrimary`, line-limit 1), optional brand (subheadline, `textSecondary`, line-limit 1, skipped when empty), optional category chip (skipped when empty).
- **Center-right**: `Spacer(minLength: 8)`.
- **Right**: `StatusBadge` (only when status is not `.ok`) above a `×N` quantity capsule (caption semibold, `pantryOat` fill at 35 % with `pantryOat` stroke).

Card background (liquid-glass pantry style): `RoundedRectangle(cornerRadius: 18)` filled with `.regularMaterial` + `pantryCream` at 35 % overlay, `pantryOat` 0.5 pt stroke, and a soft shadow (black 6 %, radius 8, y 4).

## CachedThumbnail Integration

The image is loaded via `CachedThumbnail(url: item.imageURL.flatMap { URL(string: $0) }, side: 56)`, which replaced `AsyncImage`. A nil or invalid URL string produces a nil `URL`.

`CachedThumbnail` (`ios/Inventario/Components/CachedThumbnail.swift`) decodes once and caches in memory:

- **Cache**: process-wide `NSCache` (`ThumbnailMemoryCache`, ~64 MB pixel budget, auto-purged under memory pressure). The key binds the URL *and* the render resolution (`"<url>#<maxPixelSize>"`), so a 56 pt thumbnail is never reused blurry at a larger size.
- **Downsampling**: full-size data is fetched with `URLSession.shared` (backed by the shared `URLCache`, disk included), then downsampled during decode with ImageIO (`CGImageSourceCreateThumbnailAtIndex`) on a background thread — the full bitmap never sits in memory.
- **Cancellation**: `.task(id: url)` cancels the in-flight load when the cell scrolls off-screen or the URL changes, so scrolling never leaves orphan downloads.
- **States**: loaded image (resizable, `.fill` crop to the 56×56 frame, `pantryOat` 0.5 pt inner border) · failure (`pantryOat` 35 % fill with a `photo` symbol) · loading/nil-URL (`pantryOat` 25 % fill with a `ProgressView` tinted `pantryMoss`). A nil URL resets to the placeholder state without attempting a fetch.

`contentMode` defaults to `.fill` (square crop for rows/lists); `.fit` (aspect preserved, max height `side`) is available for detail views.

## Status Badge: Hidden When Ok

The right-hand column embeds [StatusBadge](./ios-status-badge.md) only when the status is actionable:

```swift
if ItemStatus.from(statusString: item.status) != .ok {
    StatusBadge(status: ItemStatus.from(statusString: item.status))
}
```

`.ok` rows show no badge — just the quantity capsule. `ItemStatus.from` defaults unrecognised strings to `.ok`, so unknown server values also render badge-free. See [Item Status](../concepts/item-status.md) for the `expiringSoon` / `expired` badge styles.

## Category Chip

The category identifier (kebab-case server key) is resolved through `CategoryRegistry.displayName(for:)` — the single source of truth (see [Category Registry](../concepts/category-registry.md)), backed by `/api/categories` with an embedded fallback — instead of a hardcoded switch. Unknown keys fall through to the raw string.

The chip is an `HStack(spacing: 4)` with a `tag.fill` symbol and the display name (both `.caption2`, medium name weight), in `textSecondary`, inside a capsule filled with `.thinMaterial` + `pantryCream` 45 % and stroked with `pantryOat` 0.5 pt. It carries its own `accessibilityLabel`/`accessibilityHint`.

## Source Badge (Tipo Prodotto)

Rendered only when the product type is known. The typed source resolves with `source` taking precedence over the `productType` fallback, mapped tolerantly to `ProductSource` (unknown strings → `nil`, no badge):

```swift
private var productSource: ProductSource? {
    (item.source ?? item.productType).flatMap(ProductSource.init)
}
```

The badge is a non-tappable capsule in the same chip language (`.caption2` medium, `textSecondary`, `.thinMaterial` + `pantryLinen` 45 % fill, `pantryOat` 0.5 pt stroke), deliberately never using status colors. It carries `accessibilityLabel("Tipo: \(source.displayName)")`:

```swift
@ViewBuilder
private var sourceBadge: some View {
    if let source = productSource {
        Text(source.displayName)
            // ... capsule styling ...
            .accessibilityLabel("Tipo: \(source.displayName)")
    }
}
```

`ProductSource` (`food` → "Alimentare", `beauty` → "Cosmetici", `petfood` → "Pet food", `product` → "Non alimentare") and the `source` / `productType` fields on `InventoryItem` are documented in [iOS Models](../concepts/ios-models.md). The same badge appears in the scan preview "Sorgente" row ([iOS Scan Preview Sheet](./ios-scan-preview-sheet.md)) and the detail header ([iOS ItemDetailView](./ios-item-detail-view.md)).

The parent list's `FilterKey` fingerprint in `InventoryListView` hashes `item.source` and `item.productType` alongside the other visible fields (`InventoryItem` is id-only `Equatable`), so any source/type change re-derives sections and refreshes the row.

## Disclosure Indicator

The row renders **no chevron of its own**. Navigation uses tap-to-present (the parent's `onTapGesture` opens the detail sheet), so there is no `NavigationLink` disclosure indicator to duplicate — a previous double-chevron (system disclosure plus custom arrow) was removed. The only chevrons nearby belong to other views: `chevron.down` on the pantry picker menu and a single `chevron.right` on the add-product pill, both in `InventoryListView`.

## Accessibility

The row is a single accessible element (`children: .combine`, `.isButton` trait):

- **Label**: name, brand, category display name, `Tipo: <source display name>` (only when `item.source ?? item.productType` resolves to a known `ProductSource`), storage label, status label, `quantità N`, and formatted expiry date when present.
- **Value**: `"<status label>, quantità N"`.
- **Hint**: tap for details, swipe left to delete, swipe right to mark consumed.
- Dynamic Type range `.xSmall ... .accessibility3`.

## Usage

```swift
ForEach(items) { item in
    InventoryRowView(item: item)
        .contentShape(Rectangle())
        .onTapGesture { showDetailItem = item }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { /* delete */ }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { /* consume */ }
}
```

## Related

- [InventoryListView](./ios-inventory-list-view.md) — hosts the row, owns tap/swipe actions and sections
- [StatusBadge](./ios-status-badge.md)
- [ItemDetailView](./ios-item-detail-view.md)
- [Item Status](../concepts/item-status.md)
- [iOS Models](../concepts/ios-models.md)
