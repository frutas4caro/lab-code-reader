# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lab Code Reader** — An iOS SwiftUI app that decodes DataMatrix barcodes from photos of cryovial storage boxes, maps each code to its physical row/column grid position, and exports results as CSV. The real `VNDetectBarcodesRequest` Vision Framework pipeline is implemented and active; simulation mode has been replaced.

See `ios_requirements.md` for the full functional/non-functional requirements, detailed service API specs, and the complete target architecture.

## Build & Test Commands

```bash
# Build (Debug)
xcodebuild build -scheme lab-code-reader -configuration Debug -project lab-code-reader/lab-code-reader.xcodeproj

# Build (Release)
xcodebuild build -scheme lab-code-reader -configuration Release -project lab-code-reader/lab-code-reader.xcodeproj

# Run all unit tests
xcodebuild test -scheme lab-code-reader -project lab-code-reader/lab-code-reader.xcodeproj

# Run a single test method
xcodebuild test -scheme lab-code-reader -project lab-code-reader/lab-code-reader.xcodeproj -only-testing:lab-code-readerTests/lab_code_readerTests/testMethodName

# Clean
xcodebuild clean -scheme lab-code-reader -project lab-code-reader/lab-code-reader.xcodeproj
```

No linting tools are configured; Xcode's compiler warnings are the primary validation mechanism.

## Current Architecture (Simulation Mode)

The app currently uses a three-layer **Model-View-Service** structure:

### Data Model — `RawCodeData`
Struct in `GridClusteringService.swift` with normalized coordinates (`xCenter`, `yCenter` in 0.0–1.0), decoded `code` string, and optional `row`/`column` grid indices. `RawCodeData.emptyPlaceholder(row:column:)` fills missing grid cells.

### Services
- **`CameraVisionService`** (`ObservableObject`) — Owns the camera/Vision pipeline. Currently calls the free function `generateMockCodes()`. This is the integration point for `VNDetectBarcodesRequest`.
- **`GridClusteringService.swift`** — Contains two **top-level free functions** (not methods on a type):
  - `generateMockCodes(numRows:numCols:emptyProb:)` — simulates Vision output with random misalignment and missing codes
  - `runClustering(rawCodes:tolerancePercent:) -> [RawCodeData]` — core spatial clustering algorithm

### Views
- **`GridScannerApp.swift`** — `@main` entry point
- **`GridClusteringView.swift`** — Primary UI (~1,150 LOC); owns `@StateObject var cameraService`, tolerance slider (1%–10%), async result rendering
- **`ContentView.swift`** — Unused template placeholder

## Target Architecture (from `ios_requirements.md`)

The planned MVVM architecture adds layers not yet built:

```
Models/       VialRecord, ScanSession (@Model for SwiftData), ScanResult
Services/     DataMatrixScanService, GridInferenceService, AnnotationRenderer, CSVExporter
ViewModels/   ScanViewModel, HistoryViewModel
Views/        HomeView, CameraView, ScanResultView, AnnotatedImageView, ResultsTableView,
              SessionHistoryView, SettingsView
```

Persistence: **SwiftData** (iOS 17+) or **CoreData** (iOS 16 fallback) for scan session history.

## Core Clustering Algorithm

`runClustering` pipeline in `GridClusteringService.swift`:

1. Sort codes by Y-coordinate (top-to-bottom)
2. Row-band partitioning — group codes within `tolerancePercent / 100.0` of a row's running average Y
3. Sort within each row by X-coordinate (left-to-right)
4. Assign 1-indexed `row`/`column` values
5. Grid regularization — insert `EMPTY` placeholders for any missing (row, col) intersections

Tolerance is a percentage of the normalized coordinate space (1.0 = full image height).

## Key Integration Points

### Image preprocessing — orientation + tiled scanning (critical, do not revert)

`DataMatrixScanService` uses two complementary techniques to ensure reliable detection:

**Orientation bake (do not revert to CIImage path):**
`orientationBaked(image:maxDimension:)` uses `UIGraphicsImageRenderer` as the sole preprocessing step. The previous `CIImage(image:)` path double-applied EXIF rotation:
- `CIImage(image:)` incorporates `UIImage.imageOrientation` as an affine transform.
- `context.createCGImage` rendered that into an already-rotated CGImage.
- Re-wrapping with the original `imageOrientation` rotated the pixels a second time.
- Vision received a skewed image → zero barcodes found.

No CIFilter preprocessing (grayscale, contrast boost) is applied. Applying CIFilters before Vision can remove spectral cues Vision uses internally.

**Tiled scanning fallback (do not remove):**
DataMatrix codes on vial caps are ~2–5% of image width in a typical rack photograph. `VNDetectBarcodesRequest` applied to the full image finds nothing. The 3×3 tiled fallback (25% overlap) makes each code ~4× larger relative to its tile, pushing it into Vision's reliable detection range. Tile-relative normalized coordinates are converted back to full-image pixel coordinates. Duplicates (same value, centres within 60px) are deduplicated.

**Scan order:**
1. `orientationBaked()` → `.up` CGImage.
2. Full-image Vision scan.
3. If zero results: 3×3 tiled scan → merge + deduplicate.
4. `VNImageRequestHandler(cgImage:, orientation: .up, options: [:])` in all passes.

### Vision coordinate flip
Vision returns bounding boxes in normalized coordinates with **origin at bottom-left**. Convert to UIKit top-left origin before storing:
```swift
let flippedY = 1.0 - observation.boundingBox.origin.y - observation.boundingBox.height
```

### CSV schema
The exported CSV schema is `value,x,y,rect,row,col`. The `rect` column is a quoted string `"(originX, originY, width, height)"` matching the reference Python output. Width/height may be negative.

### Entitlements & Info.plist
`lab_code_reader.entitlements` has App Sandbox with read-only file access. Camera integration requires:
- `NSCameraUsageDescription` in `Info.plist`
- `NSPhotoLibraryUsageDescription` (import)
- `NSPhotoLibraryAddUsageDescription` (save annotated image)

## Integration Test Reference Files

Located at `lab-code-reader/` (sibling of the `.xcodeproj`):

| File | Purpose |
|------|---------|
| `input.jpg` | Real iPhone photo of a partially-filled cryovial storage box (~44 DataMatrix codes, portrait orientation). Primary regression image for the Vision pipeline. |
| `output.csv` | Ground-truth decode output for `input.jpg` from the reference Python pipeline. Schema: `value,x,y,rect,row,col`. Used by `ScanPipelineIntegrationTests` to validate detected values. |
| `output.jpg` | Annotated reference image (green bounding boxes, red labels). Visual reference only — pixel-exact match is not required by any test. |

**Xcode setup required:** Both `input.jpg` and `output.csv` must be added to the `lab-code-readerTests` target's **Copy Bundle Resources** build phase before integration tests can run. The test file is `lab-code-readerTests/ScanPipelineIntegrationTests.swift`. Tests require ≥ 80% of `output.csv` values to be detected.

## Color Palette

Defined in `Color+AppColors.swift` as static extensions on `Color`. All UI code must use these instead of system colors.

| Token | Hex | Role |
|---|---|---|
| `.appBlue` | `#207dbb` | Primary action, buttons, slider tint |
| `.appPurple` | `#775f9a` | Accent / secondary highlight |
| `.appOrange` | `#ea6d29` | Warnings / emphasis |
| `.appYellow` | `#edb837` | Badges / status indicators |
| `.appGreen` | `#1f9591` | Success / confirmed states |
| `.appRed` | `#a6213b` | Errors, EMPTY cell labels |
| `.appLightBlue` | `#67bddf` | Hover / selection tint |
| `.appLightTeal` | `#e6f4ef` | Surface / card backgrounds |
| `.appGray` | `#6d6e71` | Secondary text, disabled states |
| `.appLightestBlue` | `#e4f1fb` | Controls panel background |

Color assets live in `Assets.xcassets` as named `AppBlue.colorset`, etc., allowing future dark-mode variants to be added without code changes.

## Dependencies

All system frameworks — no external packages:
- `SwiftUI`, `Vision`, `Foundation`, `AVFoundation`, `CoreGraphics`, `PhotosUI`
- `SwiftData` (iOS 17+) when session persistence is implemented
