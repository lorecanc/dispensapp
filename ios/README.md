# Inventario iOS

Native SwiftUI inventory management app. Communicates with a FastAPI backend.

## Requirements

- Xcode 15.0+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
# Generate Xcode project
cd ios
xcodegen generate

# Open the project
open Inventario.xcodeproj
```

## Architecture

| Layer | Tech |
|-------|------|
| UI | SwiftUI (`@Observable`, `NavigationStack`) |
| Networking | `URLSession` + `async/await` |
| State | `@Observable` `InventoryStore` |
| Scanner | `VisionKit` `DataScannerViewController` |
| Persistence | Remote API (FastAPI) |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan` | Lookup barcode |
| POST | `/api/inventory` | Create from scan |
| POST | `/api/inventory/manual` | Create manually |
| GET | `/api/inventory` | List items |
| PATCH | `/api/inventory/{id}` | Update item |
| DELETE | `/api/inventory/{id}` | Delete item |
| GET | `/api/inventory/export` | Markdown export |

## Notes

- All UI text is in Italian.
- The backend default URL is `http://localhost:8000`, configurable in Settings.
- Barcode scanning supports EAN-13, EAN-8, UPC-E, and Code 128.
