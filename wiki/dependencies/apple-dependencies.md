---
title: "Apple Dependencies"
description: "Apple frameworks, language version, and tooling used by the Inventario iOS app"
category: "dependencies"
source_files:
  - "ios/project.yml"
  - "ios/README.md"
  - "ios/Inventario/Networking/ConnectivityMonitor.swift"
  - "ios/Inventario/Components/CachedThumbnail.swift"
  - "ios/Inventario/Networking/PantryToken.swift"
  - "ios/Inventario/Features/Scan/ScanPreviewSheet.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
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
| Network | Reachability via `NWPathMonitor` (`ConnectivityMonitor`) |
| ImageIO | Downsampling of list thumbnails (`CachedThumbnail`) |
| PhotosUI | Photo-library picking via `PhotosPicker` (contribution sheet) |
| Security | `X-Pantry-Token` persistence in Keychain (`PantryToken`) |
| UIKit (implicit) | `UIImage` as the decoded-thumbnail carrier; `NSCache` for the in-memory thumbnail cache |

### SwiftUI

Used for the entire UI layer. State management relies on `@Observable` classes (specifically `InventoryStore`). Navigation is handled via `NavigationStack`.

### VisionKit

Provides the camera-based barcode scanner through `DataScannerViewController` (see [Scanner View](../components/ios-scanner-view.md)). Supports EAN-13, EAN-8, UPC-E, and Code 128 symbologies.

### Foundation

`URLSession` with Swift concurrency (`async/await`) handles all HTTP communication with the FastAPI backend (see [iOS Networking](../concepts/ios-networking.md)). `Codable` conformance on model types enables JSON encoding and decoding. The server URL is configured via [iOS Configuration](../config/ios-config.md). `URLSession.shared` also provides the on-disk `URLCache` layer that `CachedThumbnail` builds on.

### Network

`ConnectivityMonitor` (`ios/Inventario/Networking/ConnectivityMonitor.swift`) is a minimal `@Observable` / `@MainActor` wrapper around `NWPathMonitor`: it delivers path updates on a dedicated `DispatchQueue` (`com.inventario.app.connectivity`, `.utility`) and republishes `isOnline` on the main actor. The monitor instance is injectable for tests and previews; `start()` / `stop()` manage `pathUpdateHandler` and `cancel()`, with `update(isOnline:)` kept as a seam for pure-logic tests.

### ImageIO + NSCache

`CachedThumbnail` (`ios/Inventario/Components/CachedThumbnail.swift`) replaces `AsyncImage` in lists. The pipeline is:

- `ThumbnailLoader` downloads via `URLSession.shared.data(from:)` off the main thread, then downsamples during decode with `CGImageSourceCreateWithData` + `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceThumbnailMaxPixelSize` set to `side * displayScale`), so the full-size bitmap is never held in memory.
- `ThumbnailMemoryCache` stores the decoded `UIImage` in an `NSCache<NSString, UIImage>` (thread-safe, auto-evicting under memory pressure, ~64 MB total-cost limit keyed on `url#maxPixelSize` so a small thumbnail is never reused for a larger render).
- The view loads via `.task(id: url)`, so scrolling cancels orphaned downloads; cache hits render instantly without re-download or re-decode.

### PhotosUI

`ScanPreviewSheet` (`ios/Inventario/Features/Scan/ScanPreviewSheet.swift`) imports `PhotosUI` and drives the contribution-photo flow with a `PhotosPickerItem` (`selectedPhotoItem`) bound to a `PhotosPicker`, converting the selection to `Data` plus filename/MIME for `APIClient.uploadPhoto`. No direct PhotoKit access; the picker runs out-of-process.

### Security

`PantryToken` (`ios/Inventario/Networking/PantryToken.swift`) persists `X-Pantry-Token` as a Keychain generic-password item (`kSecClassGenericPassword`, `accessibleAfterFirstUnlockThisDeviceOnly`) via `SecItemCopyMatching` / `SecItemAdd` / `SecItemDelete`. It never stores the token in UserDefaults (a legacy `pantryToken` defaults value is migrated once, then deleted) and never logs it; a missing token generates a per-install `UUID().uuidString`. `reset()` exists for tests and debugging.

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
