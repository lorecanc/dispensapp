---
title: "iOS Cached Thumbnail"
description: "SwiftUI thumbnail view with NSCache memory cache and ImageIO downsampling for smooth list scrolling"
category: "components"
source_files:
  - "ios/Inventario/Components/CachedThumbnail.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# iOS Cached Thumbnail

## Purpose

CachedThumbnail replaces `AsyncImage` in lists (see [InventoryListView](./ios-inventory-list-view.md)): it downloads the full-size image once, downsamples it to the render resolution via ImageIO in the background, and serves viewport re-entries instantly from an in-memory `NSCache`.

## Props / Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `url` | `URL?` | Yes | Remote image URL; `nil` renders the empty state |
| `side` | `CGFloat` | Yes | Thumbnail footprint in points: square side with `.fill`, max height with `.fit` |
| `cornerRadius` | `CGFloat` | No | Corner radius, default `12` |
| `contentMode` | `ContentMode` | No | `.fill` (square crop, rows/lists) or `.fit` (aspect preserved, free width), default `.fill` |

## States

| State | Rendering |
|-------|-----------|
| Loaded | `Image(uiImage:)` resizable with the configured content mode |
| Failed | `pantryOat` 35% placeholder with `photo` system icon |
| Loading | `pantryOat` 25% placeholder with `ProgressView` tinted `pantryMoss` |

`.fill` frames content to `side x side` with a clipped `RoundedRectangle` plus a `pantryOat` 0.5pt border; `.fit` uses `maxWidth: .infinity, maxHeight: side` with no border.

## Behavior

- `.task(id: url)` drives loading and cancels the previous task when the view disappears or `url` changes, avoiding orphan downloads during scroll.
- Cache key is `"\(url)#\(Int(maxPixelSize))"` where `maxPixelSize = side * displayScale`, so a 56pt thumbnail is never reused blurred for a larger render.
- `ThumbnailMemoryCache` (`NSCache<NSString, UIImage>`, `totalCostLimit` 64 MB, cost = pixels x 4 bytes) is thread-safe and self-evicts under memory pressure.
- `ThumbnailLoader.load(url:maxPixelSize:)` runs off the main thread via `URLSession.shared.data(from:)` (shared `URLCache` incl. disk comes for free), rejects non-2xx responses, and downsamples with `CGImageSourceCreateThumbnailAtIndex` (`CreateThumbnailFromImageAlways`, `WithTransform`, `ShouldCacheImmediately`, `ThumbnailMaxPixelSize`) without ever loading the full-size bitmap.

## Usage

```swift
CachedThumbnail(url: item.imageURL, side: 56)
```

```swift
CachedThumbnail(url: item.imageURL, side: 320, cornerRadius: 16, contentMode: .fit)
```

## Related

- [iOS Inventory Row View](./ios-inventory-row-view.md)
- [iOS Item Detail View](./ios-item-detail-view.md)
