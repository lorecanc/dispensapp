---
title: "iOS Configuration"
description: "iOS project configuration via XcodeGen and Info.plist for the Inventario app"
category: "config"
source_files:
  - "ios/project.yml"
  - "ios/Inventario/Info.plist"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS Configuration

This page covers build-time configuration (XcodeGen spec, Info.plist). For runtime settings (server URL, export), see the [Settings View](../components/ios-settings-view.md).

## XcodeGen Spec

The Xcode project is generated from `ios/project.yml` using [XcodeGen](../dependencies/apple-dependencies.md). The spec defines a single-target iOS application.

### Project-Level Settings

| Key | Value |
|-----|-------|
| Project name | `Inventario` |
| Bundle ID prefix | `com.inventario` |
| Deployment target | iOS 17.0 |
| Xcode version | 15.0 |
| Marketing version | `1.0.0` |
| Build number | `1` |

### Target: Inventario

| Setting | Value |
|---------|-------|
| Type | `application` |
| Platform | `iOS` |
| Source directory | `Inventario/` |
| Bundle identifier | `com.inventario.app` |
| Swift version | `5.9` |
| App icon set | `AppIcon` |
| Accent color | `AccentColor` |

Development team is left empty (set per-machine or overridden at build time).

## Info.plist

The `Info.plist` at `ios/Inventario/Info.plist` is the source of truth and is also referenced from XcodeGen via `INFOPLIST_FILE`. Some keys are managed by XcodeGen (`project.yml` `info.properties`), while others live only in the plist file.

### Camera Permission

```xml
<key>NSCameraUsageDescription</key>
<string>Per scansionare i codici a barre dei prodotti.</string>
```

Declared in both `project.yml` (under `info.properties`) and `Info.plist`. The app uses [`VisionKit.DataScannerViewController`](../components/ios-scanner-view.md) for barcode scanning, which requires camera access at runtime. The permission string is in Italian ("To scan product barcodes").

### App Transport Security

Two exceptions are configured:

| Key | Value | Source |
|-----|-------|--------|
| `NSAllowsLocalNetworking` | `true` | `project.yml` + `Info.plist` |
| `NSAllowsArbitraryLoads` | `true` | `Info.plist` only |

[`NSAllowsLocalNetworking`](../concepts/ios-networking.md) enables HTTP connections to local devices (e.g., a development server on the same network). `NSAllowsArbitraryLoads` is set only in `Info.plist` and is **not** managed through XcodeGen — this may indicate a manual edit or a legacy configuration.

### Launch Screen

```xml
<key>UILaunchScreen</key>
<dict/>
```

An empty launch screen dictionary defers to the default system behavior with no custom storyboard or configuration.

## Barcode Scanning

The app uses `VisionKit.DataScannerViewController` (iOS 16+) configured with the following barcode symbologies:

| Symbology | Notes |
|-----------|-------|
| `EAN-13` | Common on retail products worldwide |
| `EAN-8` | Short version of EAN, used on small packages |
| `UPC-E` | Zero-compressed version of UPC-A in North America |
| `Code 128` | High-density alphanumeric barcode |

The scanner uses `.balanced` quality level, single-item recognition, and highlighting enabled. Only the first detected barcode is accepted — scanning stops after the first match.

## Notable Divergence

`NSAllowsArbitraryLoads` is present in `Info.plist` but absent from `project.yml`. If this exception is no longer needed (the API is served over HTTPS on EAS Hosting), it should be removed to follow security best practices and keep the XcodeGen spec as the single source of truth. See [Getting Started](../getting-started.md) for setup instructions.
