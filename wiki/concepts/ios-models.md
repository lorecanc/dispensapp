---
title: "iOS Models"
description: "Data models used by the native iOS app — InventoryItem, ScanResult, and ItemStatus"
category: "concepts"
source_files:
  - "ios/Inventario/Models/InventoryItem.swift"
  - "ios/Inventario/Models/ScanResult.swift"
  - "ios/Inventario/Models/ItemStatus.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS Models

The iOS native target defines three models that represent inventory items, barcode scan responses, and item lifecycle status. All models are implemented as Swift value types (`struct` / `enum`) and conform to `Codable` for JSON serialization.

## InventoryItem

The primary domain model. Every item tracked in the pantry is represented by an `InventoryItem` instance.

**Conformances**: `Codable`, `Identifiable`, `Equatable`

| Field | Type | Coding Key | Description |
|-------|------|------------|-------------|
| `id` | `Int` | `id` | Unique numeric identifier |
| `barcode` | `String?` | `barcode` | EAN-13 or other barcode value |
| `name` | `String` | `name` | Display name of the product |
| `brand` | `String?` | `brand` | Brand or manufacturer |
| `expirationDate` | `Date?` | `expiration_date` | Best-by / expiration date |
| `isEstimated` | `Bool` | `is_estimated` | Whether the expiration date was estimated |
| `category` | `String?` | `category` | Product category label |
| `imageURL` | `String?` | `image_url` | URL to a product image |
| `createdAt` | `Date` | `created_at` | Timestamp of when the item was added |
| `quantity` | `Int` | `quantity` | Number of units in stock |
| `status` | `String` | `status` | Raw status value (decoded from server); maps to `ItemStatus` |

### Equality

Equality is based solely on `id`. Two `InventoryItem` values are considered equal when their identifiers match, regardless of other field changes.

```swift
static func == (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
    lhs.id == rhs.id
}
```

### Codable Implementation

`CodingKeys` maps snake_case JSON keys to camelCase Swift properties:

- `expirationDate` ← `expiration_date`
- `isEstimated` ← `is_estimated`
- `imageURL` ← `image_url`
- `createdAt` ← `created_at`

The remaining fields (`id`, `barcode`, `name`, `brand`, `category`, `quantity`, `status`) use the default key matching and are omitted from the enum.

### Date Decoding Strategy

`InventoryItem` relies on a custom `JSONDecoder.DateDecodingStrategy` named `inventoryDate` (shared with the [networking layer](../concepts/ios-networking.md)). The strategy attempts up to four formats in order:

1. ISO 8601 with fractional seconds (e.g. `2026-06-24T15:56:43.156Z`)
2. ISO 8601 without fractional seconds (e.g. `2026-06-24T15:56:43Z`)
3. ISO-like without timezone suffix (e.g. `2026-06-24T15:56:43.156523`) — decoded as UTC
4. Date-only (e.g. `2026-06-24`) — decoded as UTC

If none match, the decoder throws a `DecodingError.dataCorruptedError`.

```swift
extension JSONDecoder.DateDecodingStrategy {
    static var inventoryDate: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            // tries ISO8601DateFormatter with .withFractionalSeconds
            // falls back to ISO8601DateFormatter without fractional seconds
            // falls back to DateFormatter with "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            // falls back to DateFormatter with "yyyy-MM-dd"
        }
    }
}
```

## ScanResult

A transient model that represents the response from a barcode lookup service.

**Conformances**: `Codable`

| Field | Type | Coding Key | Description |
|-------|------|------------|-------------|
| `barcode` | `String` | `barcode` | The scanned barcode value |
| `name` | `String?` | `name` | Product name returned by the lookup |
| `brand` | `String?` | `brand` | Brand returned by the lookup |
| `categories` | `[String]` | `categories` | List of product categories |
| `imageURL` | `String?` | `image_url` | Product image URL from the lookup |
| `found` | `Bool` | `found` | Whether the barcode was found in the database |
| `message` | `String?` | `message` | Optional human-readable message (e.g. error info) |

CodingKeys follow the same snake_case convention: only `imageURL` requires explicit mapping (`image_url`); all other keys match automatically.

## ItemStatus

An enum that classifies the freshness state of an inventory item (see [Item Status](../concepts/item-status.md)). The raw string value is stored in `InventoryItem.status` and decoded directly from the server response. The enum drives the appearance of the [StatusBadge](../components/ios-status-badge.md) component.

| Case | Raw Value | Color | SF Symbol | Label (Italian) |
|------|-----------|-------|-----------|-----------------|
| `ok` | `ok` | `.green` | `checkmark.circle.fill` | Ok |
| `expiringSoon` | `expiring_soon` | `.orange` | `exclamationmark.circle.fill` | In scadenza |
| `expired` | `expired` | `.red` | `xmark.circle.fill` | Scaduto |

### Computed Properties

Each case provides three visual properties for use in SwiftUI:

- **color** — A `Color` for tinting backgrounds, badges, or text.
- **symbol** — An SF Symbol name for icon rendering.
- **label** — A human-readable Italian string for UI display.

### Factory Method

`from(statusString:)` converts a raw server value to an `ItemStatus`, defaulting to `.ok` for unrecognized strings:

```swift
static func from(statusString: String) -> ItemStatus {
    ItemStatus(rawValue: statusString) ?? .ok
}
```
