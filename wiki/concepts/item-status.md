---
title: "Item Status"
description: "The three-state lifecycle of an inventory item: ok, expiring_soon, expired"
category: "concepts"
source_files:
  - "backend/schemas.py"
  - "backend/config.py"
  - "ios/Inventario/Models/ItemStatus.swift"
  - "ios/Inventario/Features/Inventory/StatusBadge.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Item Status

Every item in the inventory carries a computed status that reflects its freshness relative to the current date. The status determines how the item is displayed, grouped, and surfaced to the user.

| Status | Condition | Backend value | iOS color | iOS icon | iOS label |
|--------|-----------|---------------|-----------|----------|-----------|
| Ok | No expiration date, or date > 3 days away | `"ok"` | `.statusFresh` (Terra) | `checkmark.circle.fill` | "Ok" |
| Expiring Soon | Date <= 3 days away (but not yet past) | `"expiring_soon"` | `.statusSoon` (Terra) | `exclamationmark.circle.fill` | "In scadenza" |
| Expired | Date is before today | `"expired"` | `.statusExpired` (Terra) | `xmark.circle.fill` | "Scaduto" |

## Backend Computation

The status is a read-only computed field on the [InventoryOut Pydantic schema](../modules/backend-schemas.md), delegating to the shared [`get_status`](../modules/backend-service-expiration.md) helper so schemas and [markdown export](../modules/backend-service-markdown-export.md) can never diverge:

```python
@computed_field
@property
def status(self) -> str:
    return get_status(self.expiration_date)
```

`get_status` evaluates three branches in order:

1. **No expiration date** — always `"ok"`. Items without a known expiration are assumed safe.
2. **Past today** — `"expired"`. The date has already passed.
3. **Within the threshold** — `"expiring_soon"`. The date falls on or before `today + 3 days`.
4. **Otherwise** — `"ok"`. The date is comfortably ahead.

### Threshold Constant

The threshold is defined in [backend/config.py](../config/backend-config.md):

```python
EXPIRING_SOON_DAYS = 3
```

This value is imported into `services/expiration.py` and used in the `timedelta` comparison inside `get_status`. Changing this value shifts the "expiring soon" window globally.

## iOS Enum

The iOS client mirrors the backend status strings with the `ItemStatus` enum, defined in `ios/Inventario/Models/ItemStatus.swift`:

```swift
enum ItemStatus: String, CaseIterable {
    case ok
    case expiringSoon = "expiring_soon"
    case expired
}
```

### Properties

Each case exposes three properties for rendering (Terra palette: `statusFresh`/`statusSoon`/`statusExpired`, mapped from the `PantryMoss` token family):

- **`color`**: `.statusFresh` (ok), `.statusSoon` (expiringSoon), `.statusExpired` (expired)
- **`symbol`**: A system SF Symbol name for each state — `checkmark.circle.fill`, `exclamationmark.circle.fill`, `xmark.circle.fill`
- **`label`**: A localized Italian display string — `"Ok"`, `"In scadenza"`, `"Scaduto"`

### Deserialization

API responses return status as a raw string. The static method `from(statusString:)` converts it back to the enum, defaulting to `.ok` for unrecognised values:

```swift
static func from(statusString: String) -> ItemStatus {
    ItemStatus(rawValue: statusString) ?? .ok
}
```

## Visual Representation

The [StatusBadge](../components/ios-status-badge.md) component renders the status as a compact capsule-shaped badge:

```swift
struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(status.color.opacity(0.14))
                    .overlay(Capsule().fill(.thinMaterial).opacity(0.35))
            }
            .overlay(
                Capsule()
                    .strokeBorder(status.color.opacity(0.28), lineWidth: 0.5)
            )
            .clipShape(Capsule())
            .symbolEffect(.bounce, value: status)
    }
}
```

The badge displays the label text and icon in the status color, on a tinted capsule with a Liquid-Glass `thinMaterial` overlay and a subtle status-colored border. The SF Symbol uses a `.bounce` effect that animates when the status value changes. Full details (accessibility, Dynamic Type) in [iOS Status Badge](../components/ios-status-badge.md).

## Usage Across Views

The status is consumed in three contexts on iOS:

- **[InventoryListView](../components/ios-inventory-list-view.md)** — Items are grouped into sections by status (ok / expiring_soon / expired), making it easy to scan what needs attention.
- **[InventoryRowView](../components/ios-inventory-row-view.md)** — Each row in the inventory list displays a `StatusBadge` for quick visual identification.
- **[ItemDetailView](../components/ios-item-detail-view.md)** — The detail view for a single item shows a `StatusBadge` so the user can see the freshness state at a glance.

On the backend, `InventoryOut.status` is automatically included in every API response. No explicit database field exists — the status is always derived at read time.

## Glossary

| Term | Definition |
|------|-----------|
| EXPIRING_SOON_DAYS | The number of days (currently 3) used as the threshold between "ok" and "expiring_soon" |
| ItemStatus | The iOS enum that maps backend status strings to colors, icons, and labels |
| StatusBadge | The SwiftUI view component that renders the status capsule for display in list rows and detail screens |
