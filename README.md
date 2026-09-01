---
title: Inventario Dispensa
emoji: 🍲
colorFrom: green
colorTo: yellow
sdk: docker
pinned: false
app_port: 7860
---

# Inventario

Pantry inventory management app — scan barcodes, track expiration dates, reduce food waste. SwiftUI iOS client + FastAPI backend over HTTP REST. Barcodes resolved via [Open Food Facts](https://world.openfoodfacts.org/); expiration dates auto-estimated from category shelf-life when not provided.

## Architettura

```
iOS App (SwiftUI)  ──HTTP──>  FastAPI Backend  ──httpx──>  Open Food Facts
                                         │
                                      SQLite
```

| Layer | Technology |
|-------|-----------|
| Backend | Python, FastAPI, SQLAlchemy, SQLite, httpx |
| iOS | Swift 5.9, SwiftUI, VisionKit, URLSession async/await |

## Struttura progetto

```
Inventario/
├── backend/                    # FastAPI backend
│   ├── main.py                 # App entry point, CORS, lifespan
│   ├── config.py               # Shelf-life mapping, OFF URL, constants
│   ├── database.py             # SQLAlchemy engine & session
│   ├── models.py               # ORM model (InventoryItem, ShoppingList)
│   ├── schemas.py              # Pydantic v2 request/response schemas
│   ├── routes/
│   │   ├── scan.py             # POST /api/scan
│   │   ├── inventory.py        # CRUD /api/inventory + export
│   │   └── shopping.py         # Shopping lists + export/check
│   ├── services/
│   │   ├── off.py              # Open Food Facts async client
│   │   ├── expiration.py       # Expiration date estimation
│   │   ├── markdown_export.py  # Inventario markdown table
│   │   └── shopping_markdown.py# Shopping list markdown checklist
│   └── tests/                  # pytest suite
├── ios/
│   ├── Inventario/             # SwiftUI app source
│   │   ├── State/              # InventoryStore, ShoppingStore (@Observable)
│   │   ├── Models/             # InventoryItem, ItemStatus, CategoryRegistry
│   │   ├── Networking/APIClient.swift
│   │   ├── Features/           # Scan, Inventory, ManualEntry, ShoppingList, Settings
│   │   ├── Components/         # EmptyStateView, QuantityStepper, CategoryPicker
│   │   └── Design/             # Color+Palette, Material+Glass
│   └── project.yml             # XcodeGen project spec
├── wiki/                       # Documentazione progetto
├── CONTRIBUTING.md             # Guida contribuzione
├── LICENSE                     # MIT
├── requirements.txt
└── inventory.db                # SQLite database (generato)
```

## Avvio rapido

### Backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
# verifica: http://127.0.0.1:8000/docs
```

Migrations Alembic eseguite automaticamente al lifecycle; fallback `Base.metadata.create_all` se Alembic non disponibile. Override DB: `DATABASE_URL=sqlite:////tmp/test.db alembic upgrade head`.

### iOS

Requisiti: Xcode 15+, iOS 17 deployment target, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd ios
xcodegen generate
open Inventario.xcodeproj
# seleziona scheme Inventario + simulator iOS 17+, Run (⌘R)
```

L'app punta di default a `http://127.0.0.1:8000` — modificabile in Impostazioni > Server > URL API. Su simulatore usa `127.0.0.1`; su device fisico sostituisci con IP del Mac nella stessa rete.

Esegui test iOS: in Xcode `Product > Test` (⌘U) o `xcodebuild test -project ios/Inventario.xcodeproj -scheme Inventario -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Palette Terra

Design token unico "Dispensa Terra" — ogni colore è un **Color Set** con varianti Light/Dark (sRGB) in `Assets.xcassets` e alias Swift in `Design/Color+Palette.swift`. Nessun colore hardcoded (`Color.red`/`orange`/`green` proibiti): usare sempre i token.

| Token | Light | Dark | Uso |
|-------|-------|------|-----|
| `PantryMoss` | `#6B7E5B` | `#A8C09A` | Primario, CTA, selezione, progresso |
| `PantryTerracotta` | `#C17A56` | `#E8A07A` | Accento, empty-state illustration |
| `PantryCream` | `#F7F3EC` | `#1E1E1C` | Background pagina / tint card |
| `PantryLinen` | `#FFFFFF` | `#2C2C2E` | Superficie card/sheet |
| `PantryEspresso` | `#2B241E` | `#F5F1E8` | Testo primario |
| `PantryStone` | `#8A827A` | `#A8A29A` | Testo secondario, bordi, icone muted |
| `PantryOat` | `#E8E0D3` | `#3A3632` | Separatore, superficie secondaria |
| `StatusFresh` | `#5A8F5E` | `#7BC080` | Stato ok / fresco |
| `StatusSoon` | `#C99A3A` | `#E6B84A` | Stato in scadenza |
| `StatusExpired` | `#B95C4A` | `#E07A65` | Stato scaduto / distruttivo |

Token semantici (`Color.textPrimary` = Espresso, `Color.textSecondary` = Stone, `Color.appBackground` = Cream, `Color.surface` = Linen, `Color.accentTerra` = Moss, `Color.borderTerra` = Stone 25% — vedi `Color+Palette.swift`).

**Material vs Glass (HIG):** `Material` (`regular`/`thin`/`ultraThin`) su content — card, row, form, badge. `glassEffect` (iOS 26+) solo su navigation chrome — TabBar, Toolbar, NavigationBar, sheet chrome, scanner overlay. Helper `pantryCardBackground()` e `pantryGlassChrome()` in `Design/Material+Glass.swift`. Increase Contrast / Reduce Transparency sono gestiti dal sistema perché i colori derivano da Color Set + Material/glass nativi; non disattivare mai `reduceTransparency` manualmente.

## Markdown lista spesa — specifica

Due export `text/markdown` (con escaping `|` → `\|` e newline → spazio per prevenire injection):

**Inventario** `GET /api/inventory/export` (`backend/services/markdown_export.py`):

```markdown
# 🍲 Inventario Dispensa

| Prodotto | Brand | Quantità | Scadenza | Stato | Note |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Latte | Parmalat | 2 | 02/09/2026 | 🟢 OK |  |
| Yogurt | Muller | 1 | 30/08/2026 | 🔴 Scaduto | ⚠️ Scadenza stimata |
```

**Shopping list** `GET /api/pantries/{id}/shopping-lists/{listId}/export` (`backend/services/shopping_markdown.py`):

```markdown
# 🛒 Spesa settimanale

## 🧊 Frigo

- [ ] Latte x2
- [x] Yogurt x1

## 🍷 Cantina

- [ ] Vino x2

## 🏠 Dispensa

- [ ] Pasta x1

## 📦 Altro

- [ ] Prodotto custom x1
```

Regole: raggruppamento per `compartment` normalizzato (`frigo`/`cantina`/`dispensa`/`altro`; vuoto → `dispensa`), checklist `- [ ]` / `- [x]` da `checked`, quantità sempre `xN`, lista vuota → `_Nessun articolo_`. Condivisione via `ShareLink` in iOS (`ShoppingListView`, `SettingsView`).

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan` | Lookup barcode via Open Food Facts |
| POST | `/api/inventory` | Create item from scan |
| POST | `/api/inventory/manual` | Create item manually |
| GET | `/api/inventory` | List all items |
| PATCH | `/api/inventory/{id}` | Update item |
| DELETE | `/api/inventory/{id}` | Delete item |
| GET | `/api/inventory/export` | Export inventario as Markdown |
| GET/POST | `/api/pantries/{id}/shopping-lists` | List/create shopping lists |
| GET | `/api/pantries/{id}/shopping-lists/{listId}` | Get list with items |
| POST | `/api/pantries/{id}/shopping-lists/{listId}/items` | Add item (compartment: frigo/cantina/dispensa/altro) |
| PATCH | `/api/pantries/{id}/shopping-lists/{listId}/items/{itemId}` | Toggle checked |
| DELETE | `/api/pantries/{id}/shopping-lists/{listId}/items/{itemId}` | Delete item |
| GET | `/api/pantries/{id}/shopping-lists/{listId}/export` | Export lista spesa as Markdown |
| GET | `/api/pantries/{id}/shopping-lists/{listId}/check` | Cross-check vs dispensa |
| GET | `/api/suggestions?q=` | Suggerimenti basati su scansioni frequenti |

## Accessibilità

- Card dispensa: `accessibilityLabel`/`Value`/`Hint` combinati (nome, brand, categoria, stato, quantità, scadenza) + `dynamicTypeSize(.xSmall ... .accessibility3)` e `isButton`.
- Swipe actions: label/hint espliciti ("Elimina X", "Segna consumato").
- Scanner overlay: pulsante chiusura con label/hint, empty state scanner con label.
- Shopping checklist: riga `combine` con label/value/hint + pulsante check con stato, badge dispensa con hint, swipe elimina con hint.
- Empty states e chip categoria leggono categoria e stato (StatusBadge con label/value/hint). Chip filtro con `isSelected` + hint/value.
- `QuantityStepper` con `accessibilityAdjustableAction`. Nessun colore fuori palette.

## Contribuire

Vedi [CONTRIBUTING.md](./CONTRIBUTING.md) — setup, test (`pytest` + Xcode tests), PR flow.

## Licenza

MIT — vedi [LICENSE](./LICENSE).

## Documentazione

Vedi [wiki](./wiki/index.md) per architettura, componenti, concetti e configurazione.

## Note

- Tutti i testi UI sono in italiano.
- Barcode: EAN-13, EAN-8, UPC-E, Code 128 via VisionKit `DataScannerViewController`.
- Scadenze stimate segnate con `⚠️` quando categoria senza data esplicita.
