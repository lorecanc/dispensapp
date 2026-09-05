---
title: "iOS Invite Members Sheet"
description: "Pantry invite-link creation, read-only member list, and token-accept flow for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/InviteMembersSheet.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# iOS Invite Members Sheet

## Purpose

195-line SwiftUI sheet for managing [shared-pantry](../concepts/pantry-sharing.md) membership. All business logic stays in `InventoryStore` (`createInvite`, `fetchMembers`, `acceptInviteToken`); the view only renders three `List` sections (invite link, members, accept invite), maps `APIError` to user-facing strings via `inviteErrorText`, and never persists or logs the invite token.

## Props / Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `store` | `InventoryStore` (`@Environment`) | yes | Source of `selectedPantryId`, `inviteLink`, `inviteError`, `isInviteLoading`, `members` |
| `dismiss` | `DismissAction` (`@Environment`) | yes | Closes the sheet via "Chiudi" toolbar button |
| `tokenInput` | `String` (`@State`) | no | Pasted invite token, trimmed before use and cleared after accept |
| `showAcceptConfirm` | `Bool` (`@State`) | no | Drives the "Accettare l'invito?" confirmation dialog |
| `didCopy` | `Bool` (`@State`) | no | Shows the "Copiato negli appunti" feedback after copy |

## Usage

Presented as a sheet with `.medium` / `.large` detents and a visible drag indicator, wrapped in a `NavigationStack` titled "Membri dispensa":

```swift
InviteMembersSheet()
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
```

Sections:

- **Link invito** — honest copy ("Chi ha il link può unirsi", "Il link scade tra 7 giorni"), loading indicator while `isInviteLoading`, owner-only "Crea link invito" button (`store.createInvite`), then `ShareLink` + "Copia link" (`UIPasteboard`) once `store.inviteLink` exists, plus inline `inviteErrorText` error label.
- **Membri** — read-only list (`role.capitalized` + abbreviated `joinedAt`); `PantryMember` exposes no member token so UI removal is impossible. Empty state: "Nessun membro oltre a te." Footer: "Solo l'owner può rimuovere membri."
- **Accetta invito** — `TextField` (no autocapitalization/autocorrect, 44pt touch target) + "Accetta invito" button gated on non-empty trimmed token, confirmed via dialog calling `store.acceptInviteToken(trimmedToken)` then clearing the field.

## Error Mapping

`inviteErrorText(_:)` maps `APIError` to context-honest strings without ever including the token:

| Error | Text |
|-------|------|
| `.http(401/403)` | "Solo l'owner può invitare/rimuovere." |
| `.http(404/410)`, `.notFound` | "Link scaduto, chiedine uno nuovo." |
| `.http(409)` | "Sei già membro di questa dispensa." |
| `.offline` | "Nessuna connessione. Riprova." |
| `.transport` | "Rete non disponibile. Riprova." |
| `.http(default)`, `.invalidURL`, `.decoding` | "Operazione non riuscita. Riprova." |

## Related

- [iOS Inventory List View](./ios-inventory-list-view.md)
