---
title: "Apple Dependencies"
description: "Apple frameworks, language version, and tooling used by the Inventario iOS app"
category: "dependencies"
source_files:
  - "ios/project.yml"
  - "ios/README.md"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Apple Dependencies

## Overview

The Inventario iOS app uses only Apple-provided frameworks. There are no third-party dependencies. The project is a native SwiftUI application targeting iOS 17.0+.

## Frameworks

| Framework | Usage |
|-----------|-------|
| SwiftUI | All views and navigation built with `@Observable` and `NavigationStack` |
| VisionKit | Barcode scanning via `DataScannerViewController` |
| Foundation | `URLSession` with `async/await` for networking, `Codable` for JSON serialization |

### SwiftUI

Used for the entire UI layer. State management relies on `@Observable` classes (specifically `InventoryStore`). Navigation is handled via `NavigationStack`.

### VisionKit

Provides the camera-based barcode scanner through `DataScannerViewController` (see [Scanner View](../components/ios-scanner-view.md)). Supports EAN-13, EAN-8, UPC-E, and Code 128 symbologies.

### Foundation

`URLSession` with Swift concurrency (`async/await`) handles all HTTP communication with the FastAPI backend (see [iOS Networking](../concepts/ios-networking.md)). `Codable` conformance on model types enables JSON encoding and decoding. The server URL is configured via [iOS Configuration](../config/ios-config.md).

## Language & Platform

| Requirement | Version |
|-------------|---------|
| Swift | 5.9 |
| iOS deployment target | 17.0 |
| Xcode | 15.0+ |

## Project Generation

The Xcode project is not committed to the repository. Instead, it is generated from a declarative specification using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios
xcodegen generate
```

The generation config lives in [`ios/project.yml`](../../ios/project.yml) and defines the target, build settings, Info.plist properties, and Swift version.
