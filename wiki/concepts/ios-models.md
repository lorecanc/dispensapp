---
title: "iOS Models"
description: "Data models used by the native iOS app — InventoryItem, ScanResult, CategoryRegistry, Pantry, ConsumptionEvent, and shopping models"
category: "concepts"
source_files:
  - "ios/Inventario/Models/InventoryItem.swift"
  - "ios/Inventario/Models/ScanResult.swift"
  - "ios/Inventario/Models/ItemStatus.swift"
  - "ios/Inventario/Models/CategoryRegistry.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingModels.swift"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# iOS Models

The iOS native target defines its domain as Swift value types (`struct` / `enum`), all `Codable` for JSON serialization. Core inventory models live in `ios/Inventario/Models/`; multi-pantry, history, and category DTOs are file-scope structs in `Networking/APIClient.swift` (shared with `InventoryStore`); shopping-list models live in `Features/ShoppingList/ShoppingModels.swift`.

## InventoryItem

The primary domain model. Every item tracked in the pantry is an `InventoryItem`.

**Conformances**: `Codable`, `Identifiable`, `Equatable`

| Field | Type | Coding Key | Description |
|-------|------|------------|-------------|
| `id` | `Int` | `id` | Unique numeric identifier |
| `barcode` | `String?` | `barcode` | EAN-13 or other barcode value |
| `name` | `String` | `name` | Display name of the product |
| `brand` | `String?` | `brand` | Brand or manufacturer |
| `expirationDate` | `Date?` | `expiration_date` | Best-by / expiration date |
| `isEstimated` | `Bool` | `is_estimated` | Whether the expiration date was estimated |
| `category` | `String?` | `category` | Canonical category key (see `CategoryRegistry`) |
| `imageURL` | `String?` | `image_url` | Product image URL |
| `createdAt` | `Date` | `created_at` | Timestamp of when the item was added |
| `quantity` | `Int` | `quantity` | Number of units in stock |
| `status` | `String` | `status` | Raw status value from server; maps to `ItemStatus` |
| `source` | `String?` | `source` | Product source (`food`\|`beauty`\|`petfood`\|`product`); nil when unset or backend predates the field |
| `productType` | `String?` | `product_type` | Product type from backend; nil when unset or backend predates the field |

### Equality

Equality is based solely on `id`:

```swift
static func == (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
    lhs.id == rhs.id
}
```

### Date Decoding Strategy

`InventoryItem` relies on the shared `JSONDecoder.DateDecodingStrategy.inventoryDate` (also used by the [iOS Networking](./ios-networking.md)). It tries five formats in order:

1. ISO 8601 with fractional seconds (e.g. `2026-06-24T15:56:43.156Z`)
2. ISO 8601 without fractional seconds (e.g. `2026-06-24T15:56:43Z`)
3. Naive timestamp without fractional seconds and without timezone suffix (e.g. `2026-09-06T10:02:00`, format `yyyy-MM-dd'T'HH:mm:ss`) — decoded as UTC
4. ISO-like without timezone suffix with fractional seconds (e.g. `2026-06-24T15:56:43.156523`, format `yyyy-MM-dd'T'HH:mm:ss.SSSSSS`) — decoded as UTC
5. Date-only (e.g. `2026-06-24`) — decoded as UTC

Otherwise it throws `DecodingError.dataCorruptedError`.

Implementation detail: the five formatters are shared `static` instances (two `ISO8601DateFormatter` with different `formatOptions`, three `DateFormatter` with `en_US_POSIX` locale and UTC timezone) to avoid allocating a formatter per date field. The ISO formatters are marked `nonisolated(unsafe)` because `ISO8601DateFormatter` lacks a `Sendable` annotation but is thread-safe once configured; the two ISO variants are separate instances so concurrent decoding never mutates shared `formatOptions`.

## ScanResult

Transient model for a barcode-lookup response.

**Conformances**: `Codable`, `Sendable`

| Field | Type | Coding Key | Description |
|-------|------|------------|-------------|
| `barcode` | `String` | `barcode` | Scanned barcode value |
| `name` | `String?` | `name` | Product name from lookup |
| `brand` | `String?` | `brand` | Brand from lookup |
| `categories` | `[String]` | `categories` | Product category list |
| `imageURL` | `String?` | `image_url` | Product image URL |
| `found` | `Bool` | `found` | Whether the barcode was found |
| `message` | `String?` | `message` | Optional human-readable message |
| `source` | `String?` | `source` | Raw product source from backend; nil with backends predating the field |
| `productType` | `String?` | `product_type` | Product type from backend; nil with backends predating the field |

Only `imageURL`, `suggestedCategory` (`suggested_category`), and `productType` (`product_type`) need explicit `CodingKeys` mappings. `source` and `productType` are additive `var` fields with `nil` defaults, so decoding tolerates payloads from older backends and the memberwise initializer is unchanged for existing call sites. See the [Scan API](../api/scan.md) for the backend fields.

### needsEnrichment

Computed helper driving the enrich-after-scan flow. Returns `true` when the product is missing or has incomplete data:

```swift
var needsEnrichment: Bool {
    guard found else { return true }
    if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
    return imageURL == nil
}
```

## ProductSource

Typed view over the raw `source` string shared by `ScanResult` and `InventoryItem` (see the [Scan API](../api/scan.md) and the [iOS Networking](./ios-networking.md)).

**Conformances**: `Codable`, `Sendable`, `Hashable`, `CaseIterable`

| Case | Raw Value | `displayName` (Italian) |
|------|-----------|-------------------------|
| `food` | `food` | Alimentare |
| `beauty` | `beauty` | Cosmetici |
| `petfood` | `petfood` | Pet food |
| `product` | `product` | Non alimentare |

`ScanResult.sourceEnum` is the tolerant typed accessor — unknown raw values decode to `nil`, never a `DecodingError`:

```swift
var sourceEnum: ProductSource? { source.flatMap(ProductSource.init) }
```

## ItemStatus

Enum classifying item freshness (see [Item Status](../concepts/item-status.md)). The raw string is stored in `InventoryItem.status`. Drives [StatusBadge](../components/ios-status-badge.md).

| Case | Raw Value | Color | SF Symbol | Label (Italian) |
|------|-----------|-------|-----------|-----------------|
| `ok` | `ok` | `.green` | `checkmark.circle.fill` | Ok |
| `expiringSoon` | `expiring_soon` | `.orange` | `exclamationmark.circle.fill` | In scadenza |
| `expired` | `expired` | `.red` | `xmark.circle.fill` | Scaduto |

Each case exposes `color`, `symbol`, and `label`. `from(statusString:)` maps a raw server value to `ItemStatus`, defaulting to `.ok` for unknown strings.

## CategoriesResponse and CategoryRegistry

`CategoriesResponse` (`APIClient.swift`) decodes `GET /api/categories`. Only `categories` and `compartmentMap` are consumed; the rest stay optional so backend evolution does not break decoding.

**Conformances**: `Codable`, `Equatable`, `Sendable`

| Field | Type | Coding Key |
|-------|------|------------|
| `categories` | `[Category]` | `categories` |
| `defaultShelfLifeDays` | `Int?` | `default_shelf_life_days` |
| `labels` | `[String: String]?` | `labels` |
| `compartments` | `[String]?` | `compartments` |
| `compartmentMap` | `[String: String]` | `compartment_map` |

`Category` holds `key`, `label`, `shelfLifeDays?` (`shelf_life_days`), and `compartment?` (nil when the key has no compartment mapping).

`CategoryRegistry` (`Models/CategoryRegistry.swift`) is the iOS source of truth for category keys/labels and the category-key → compartment map (see [Category Registry](../concepts/category-registry.md)). Whoever fetches `/api/categories` (store, T10 consumer) calls `update(with:)`; the embedded snapshot (copy of backend `CATEGORY_LABELS` + `COMPARTMENT_MAP`, ~26 categories) is the offline/first-launch fallback only. An empty `categories` list is ignored so a degraded server response never wipes the registry; `resetToEmbedded()` restores the fallback. All access is serialized through an `NSLock`.

Public API: `categories` (`[(key:label:)]`), `validCategoryKeys`, `displayName(for:)`, `compartmentMap`.

## Pantry, Invite, PantryMember

File-scope structs in `APIClient.swift`, shared with `InventoryStore` (see [Pantries API](../api/pantries.md)). All are `Codable`, `Equatable`, `Sendable` (`Pantry` is also `Identifiable`).

- **Pantry**: `id: Int`, `name: String`, `createdAt: Date` (`created_at`).
- **Invite**: `id: Int`, `pantryId: Int` (`pantry_id`), `token: String`, `status: String`, `expiresAt: Date` (`expires_at`), `createdAt: Date` (`created_at`).
- **PantryMember**: `pantryId: Int` (`pantry_id`), `role: String`, `joinedAt: Date` (`joined_at`). Note: no member token is exposed, so the invite-members UI treats the member list as read-only.

## ConsumptionEvent

History entry returned by `APIClient.history(pantryId:itemId:)` and cached per item in `InventoryStore.history: [Int: [ConsumptionEvent]]` (see [Inventory Consume & History](../concepts/inventory-consume-history.md)).

**Conformances**: `Codable`, `Identifiable`, `Equatable`, `Sendable`

| Field | Type | Coding Key |
|-------|------|------------|
| `id` | `Int` | `id` |
| `pantryId` | `Int` | `pantry_id` |
| `itemId` | `Int?` | `item_id` |
| `nameSnapshot` | `String` | `name_snapshot` |
| `barcode` | `String?` | `barcode` |
| `delta` | `Int` | `delta` |
| `reason` | `String?` | `reason` |
| `createdAt` | `Date` | `created_at` |

## Shopping Models

`Features/ShoppingList/ShoppingModels.swift` holds the shopping-list domain (see [Shopping Departments](../concepts/shopping-departments.md); all `Codable`, `Equatable`; lists/items also `Identifiable` with id-only equality):

- **ShoppingList**: `id`, `pantryId` (`pantry_id`), `name`, `createdAt` (`created_at`), `items: [ShoppingListItem]`.
- **ShoppingListItem**: `id`, `shoppingListId` (`shopping_list_id`), `name`, `quantity`, `checked` (var), `compartment: String?`, `createdAt` (`created_at`).
- **Suggestion**: `barcode` (used as `id`), `name`, `category?`, `timesScanned` (`times_scanned`).
- **PantryCheckItem / PantryCheckResponse**: `PantryCheckItem` (`id`, `name`, `inPantry`, `status`) wrapped in `PantryCheckResponse(items:)`.
- **Compartment**: 10-case supermarket-aisle enum (`Ortofrutta`, `Latticini e Uova`, `Salumi e Formaggi`, `Carne e Pesce`, `Surgelati`, `Dispensa Secca`, `Bevande`, `Cantina`, `Forno e Panetteria`, `Igiene e Casa`) with `icon` (SF Symbol), `supermarketOrder` traversal order (aligned with backend `SUPER_MARKET_COMPARTMENTS`), legacy-name normalization (`frigo`/`cantina`/`dispensa`/`altro`), and inference cascade category-via-registry → name-keywords → default `Dispensa Secca`.
