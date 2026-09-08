---
title: "iOS Configuration"
description: "iOS project configuration via XcodeGen and Info.plist for the Inventario app"
category: "config"
source_files:
  - "ios/project.yml"
  - "ios/Inventario/Info.plist"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# iOS Configuration

This page covers build-time configuration (XcodeGen spec, Info.plist). For runtime settings (server URL, export), see the [Settings View](../components/ios-settings-view.md).

## XcodeGen Spec

The Xcode project is generated from `ios/project.yml` using [XcodeGen](../dependencies/apple-dependencies.md). The spec defines an application target plus a unit-test bundle. The generated project (`ios/Inventario.xcodeproj/project.pbxproj`) mirrors these settings.

### Project-Level Settings

| Key | Value |
|-----|-------|
| Project name | `Inventario` |
| Bundle ID prefix | `com.inventario` |
| Deployment target | iOS 17.0 |
| Marketing version | `1.0.0` |
| Build number | `1` |

There is no `xcodeVersion` pin (the old `15.0` value was removed as inconsistent with the toolchain in use). `DEVELOPMENT_TEAM` is set to `"4YK6GDPC39"` on the `Inventario` app target, with an empty-string default (`""`) at the project base level (overridable per-machine at build time).

### Target: Inventario

| Setting | Value |
|---------|-------|
| Type | `application` |
| Platform | `iOS` |
| Source directory | `Inventario/` |
| Bundle identifier | `com.inventario.app` |
| Swift version | `5` |
| `INFOPLIST_FILE` | `Inventario/Info.plist` |
| App icon set | `AppIcon` |
| Accent color | `AccentColor` |

### Target: InventarioTests

| Setting | Value |
|---------|-------|
| Type | `bundle.unit-test` |
| Platform | `iOS` |
| Source directory | `InventarioTests/` |
| Bundle identifier | `com.inventario.tests` |
| Swift version | `5` |
| `GENERATE_INFOPLIST_FILE` | `YES` |
| Dependency | `Inventario` target |

The test bundle generates its own Info.plist at build time, unlike the app target which uses the hand-maintained file.

### Hand-Maintained Info.plist

`Info.plist` at `ios/Inventario/Info.plist` is hand-maintained and referenced via `INFOPLIST_FILE`. There is deliberately no `info:` block in `project.yml`: adding one would make XcodeGen regenerate and clobber keys that are not representable in the spec (orientations, `CFBundleURLTypes`).

## Info.plist

### Camera Permission

```xml
<key>NSCameraUsageDescription</key>
<string>Per scansionare i codici a barre dei prodotti.</string>
```

The app uses [`VisionKit.DataScannerViewController`](../components/ios-scanner-view.md) for barcode scanning, which requires camera access at runtime. The permission string is in Italian ("To scan product barcodes").

### App Transport Security

```xml
<key>NSAllowsArbitraryLoads</key>
<false/>
<key>NSAllowsLocalNetworking</key>
<true/>
```

[`NSAllowsLocalNetworking`](../concepts/ios-networking.md) enables HTTP connections to local devices (e.g., a development server on the same network). `NSAllowsArbitraryLoads` is explicitly `false`, so all other connections require HTTPS.

### Supported Orientations

iPhone excludes upside-down; iPad allows all four orientations:

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
  <string>UIInterfaceOrientationPortrait</string>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
  <string>UIInterfaceOrientationPortrait</string>
  <string>UIInterfaceOrientationPortraitUpsideDown</string>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

These keys live only in `Info.plist` and are not representable in the XcodeGen `info:` spec — one reason the plist is hand-maintained.

### URL Scheme

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>inventario</string>
    </array>
  </dict>
</array>
```

Registers the `inventario://` deep-link scheme. Like orientations, this lives only in `Info.plist`.

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
