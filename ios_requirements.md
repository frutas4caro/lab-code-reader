# iOS Vial DataMatrix Reader — Requirements Document

## Overview

Build an iOS application that scans a photograph of a cryovial storage box (containing a grid of vials, each with a DataMatrix code on its cap), decodes all DataMatrix codes in the image, maps each decoded value to its physical grid position (row/column), and presents the results in a structured, exportable format.

This app replicates and extends the functionality of a Python script (`read_datamatrix.py`) that uses `pylibdmtx` + OpenCV to batch-decode DataMatrix codes from a single image of a vial rack.

---

## Target Platform

- **Platform:** iOS 16.0+
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Xcode:** 15+
- **Device:** iPhone (primary), iPad (secondary/supported)

---

## Core Concepts

### What the app does
1. The user photographs (or imports) a top-down image of a cryovial storage box — typically an 8×8, 9×9, or 10×10 grid of vials, each with a small DataMatrix barcode printed on its cap.
2. The app decodes all DataMatrix codes found in the image.
3. It maps each decoded value to its row/column position in the physical grid, based on the detected spatial coordinates of each code.
4. It displays an annotated preview of the image with overlaid bounding boxes and labels.
5. It presents the decoded values in a sorted grid/table view.
6. It allows the user to export the results as CSV.

### Key domain terms
- **DataMatrix:** A 2D matrix barcode symbology (not QR code). Vial caps use DataMatrix codes, not QR codes.
- **Vial rack / storage box:** A physical grid container holding cryovials, typically organized in rows and columns (e.g., 9×9 = 81 positions).
- **Grid position (row, col):** The row/column location of a vial within the rack, inferred from the spatial coordinates of its DataMatrix code in the image.
- **Tolerance:** A pixel-distance threshold used to group codes that are approximately in the same row or column, accounting for minor misalignment in the photograph.

---

## Functional Requirements

### FR-1: Image Acquisition

- **FR-1.1** The app must allow the user to capture a new photo using the device camera (`AVFoundation` / `UIImagePickerController` or `PhotosUI.PhotosPicker`).
- **FR-1.2** The app must allow the user to import an existing image from the photo library.
- **FR-1.3** The camera capture mode must support still photo capture; video/live scanning is not required for the initial version.
- **FR-1.4** The app should provide a viewfinder guide overlay (a square crop guide) to help the user frame the vial box within the shot.
- **FR-1.5** The acquired image must be stored in memory for processing; it does not need to be saved to the camera roll unless the user explicitly requests it.

### FR-2: DataMatrix Decoding

- **FR-2.1** The app must decode DataMatrix barcodes (ISO/IEC 16022) — **not** QR codes or Code128. This is a hard requirement because vial cap labels specifically use the DataMatrix symbology.
- **FR-2.2** Apple's native `Vision` framework (`VNDetectBarcodesRequest`) supports DataMatrix (`VNBarcodeSymbologyDataMatrix`) and **must be used as the primary decoder**.
- **FR-2.3** The decoder must handle images containing **multiple DataMatrix codes** simultaneously (batch decoding in a single pass).
- **FR-2.4** Each decoded result must retain:
  - The decoded string value (payload)
  - The bounding box of the code in image coordinates (`CGRect` in normalized Vision coordinates, converted to pixel coordinates)
  - The center point of the bounding box (used for grid position inference)
- **FR-2.5** The app must handle non-ASCII payloads gracefully by falling back to a hex-encoded string representation.
- **FR-2.6** Before decoding, the image must be normalised using `UIGraphicsImageRenderer` to bake any EXIF/UIImage orientation into the pixel buffer in a single pass. Do **not** use `CIImage(image:)` for orientation normalisation — it incorporates the orientation as an affine transform on the CIImage coordinate space, causing double-rotation if the CGImage is later re-wrapped with the original orientation tag. `UIGraphicsImageRenderer.draw(in:)` resolves this correctly and always produces a `.up` CGImage. No additional CIFilter preprocessing (grayscale, contrast) is applied before passing to Vision; applying such filters can remove spectral information Vision uses internally.
- **FR-2.7** Downsampling (when the longest dimension exceeds `maxDimension`) must happen inside the `UIGraphicsImageRenderer` pass described in FR-2.6.
- **FR-2.8** Because individual DataMatrix codes in rack photographs are typically small relative to the full image (each code ~2–5% of image width), `VNDetectBarcodesRequest` on the full image may return zero results. The decoder must implement a **tiled scanning fallback**:
  1. Attempt a full-image scan first.
  2. If zero detections are returned, divide the image into a 3×3 grid of overlapping tiles (25% overlap on each edge) and scan each tile independently.
  3. Convert tile-relative normalized Vision coordinates back into full-image pixel coordinates before storing.
  4. Deduplicate results across overlapping tiles: two detections with the same value whose centres are within 60px are considered the same physical barcode; keep only the first occurrence.
  `VNImageRequestHandler` must be initialised with `orientation: .up` in all cases (full image and each tile) since orientation is already baked.

### FR-3: Grid Position Inference

- **FR-3.1** After decoding, the app must infer each vial's row and column position within the rack grid from the spatial coordinates of its DataMatrix code.
- **FR-3.2** Row grouping: vials with similar Y-coordinates (within a configurable tolerance) are considered to be in the same row.
- **FR-3.3** Column grouping: vials with similar X-coordinates (within a configurable tolerance) are considered to be in the same column.
- **FR-3.4** The tolerance value (pixel distance threshold for grouping) must be configurable. Default: `100` points (matching the Python script's `TOLERANCE = 100`). This value should be adjustable in app settings.
- **FR-3.5** Rows must be numbered top-to-bottom (row 0 = topmost vials).
- **FR-3.6** Columns must be numbered left-to-right (col 0 = leftmost vials).
- **FR-3.7** The final result set must be sorted by (row, col) — row-major order.
- **FR-3.8** Each decoded vial record must carry: `{ value: String, row: Int, col: Int, centerX: CGFloat, centerY: CGFloat, boundingRect: CGRect }`.

### FR-4: Annotated Image Overlay

- **FR-4.1** After decoding, the app must render an annotated version of the input image with:
  - A green bounding rectangle drawn around each detected DataMatrix code.
  - A label displaying the sequential index and decoded value (e.g., `"1: A00123"`) rendered above each bounding box in red text.
- **FR-4.2** The annotated image must be rendered using Core Graphics (`CGContext`) or `UIGraphicsImageRenderer` — not a live SwiftUI overlay — so that the annotation is baked into an exportable `UIImage`.
- **FR-4.3** The annotated image must be displayed in a zoomable/pannable image viewer within the app (e.g., using a `ScrollView` with `ZoomScale` or a `UIScrollView`-backed `UIViewRepresentable`).
- **FR-4.4** The user must be able to save the annotated image to the photo library (requires `NSPhotoLibraryAddUsageDescription` in `Info.plist`).

### FR-5: Results Table View

- **FR-5.1** The decoded results must be displayed in a table/list view showing at minimum: sequential index, row, column, and decoded value for each vial.
- **FR-5.2** The table must be sorted in row-major order (row 0 col 0, row 0 col 1, …, row N col M).
- **FR-5.3** The table must indicate the total count of successfully decoded codes.
- **FR-5.4** If no codes are detected, the app must display a clear message (e.g., "No DataMatrix codes detected. Try improving lighting or image focus.").
- **FR-5.5** Individual rows in the table must be tappable to highlight the corresponding vial in the annotated image view.

### FR-6: CSV Export

- **FR-6.1** The app must be able to export the results as a CSV file with the schema: `value,x,y,rect,row,col`. The `rect` column encodes the pixel-space bounding rectangle as `"(originX, originY, width, height)"` — a quoted string matching the format produced by the reference Python pipeline. Example row: `A00183,600.5,826.5,"(600, 854, 1, -55)",8,6`. Note that width/height can be negative when the Vision bounding box origin is not the top-left corner of the detected region.
- **FR-6.2** Export must use iOS share sheet (`UIActivityViewController`) so the user can save to Files, share via AirDrop, email, etc.
- **FR-6.3** The exported CSV filename must include a timestamp (e.g., `vials_2026-02-20_143022.csv`).
- **FR-6.4** The CSV must use standard comma-separated format with a header row.

### FR-7: Session Management

- **FR-7.1** The app must support multiple scan sessions. Each scan produces one session with its image, decoded results, and metadata.
- **FR-7.2** Recent sessions must be persisted locally using `SwiftData` (iOS 17+) or `CoreData` (if targeting iOS 16).
- **FR-7.3** Each persisted session must store: timestamp, total vial count, thumbnail of annotated image, and serialized CSV data.
- **FR-7.4** The user must be able to browse, view, and re-export past sessions from a history list screen.
- **FR-7.5** The user must be able to delete sessions from history (swipe-to-delete).

---

## Non-Functional Requirements

### NFR-1: Performance
- **NFR-1.1** The full decode pipeline (image preprocessing → Vision detection → grid inference → annotation rendering) must complete in under **5 seconds** on an iPhone 12 or newer for a typical 9×9 rack image at 12 MP.
- **NFR-1.2** Image processing must run on a background thread (`Task` / `DispatchQueue.global`). The UI must remain responsive during processing.
- **NFR-1.3** A loading indicator (progress view or spinner) must be shown while processing is in progress.

### NFR-2: Accuracy
- **NFR-2.1** The app must correctly decode all DataMatrix codes that are clearly visible and in focus in the input image.
- **NFR-2.2** The grid position inference must correctly assign row/column positions for standard rack configurations (8×8, 9×9, 10×10) when the image is captured approximately top-down and level.

### NFR-3: Privacy & Permissions
- **NFR-3.1** Camera usage must declare `NSCameraUsageDescription` in `Info.plist`.
- **NFR-3.2** Photo library read access must declare `NSPhotoLibraryUsageDescription`.
- **NFR-3.3** Photo library write (save annotated image) must declare `NSPhotoLibraryAddUsageDescription`.
- **NFR-3.4** No data must be transmitted off-device. All processing is local.
- **NFR-3.5** The app must not require an account or network connectivity to function.

### NFR-4: Code Quality
- **NFR-4.1** Use `async/await` for all asynchronous operations (no completion-handler callbacks).
- **NFR-4.2** Follow MVVM architecture: `View` → `ViewModel` (ObservableObject / `@Observable`) → `Model` / `Service`.
- **NFR-4.3** Image processing logic must be isolated in a dedicated `DataMatrixScanService` (or equivalent) that is independently testable.
- **NFR-4.4** Grid inference logic must be in a pure function / struct (no side effects, no UI dependencies) so it can be unit tested.
- **NFR-4.5** No third-party libraries are required — all functionality must be achievable with native Apple frameworks (`Vision`, `AVFoundation`, `CoreGraphics`, `SwiftData`, `PhotosUI`).

---

## Architecture

### Recommended Layer Structure

```
VialScanner/
├── App/
│   └── VialScannerApp.swift           # @main entry point, SwiftData container setup
│
├── Models/
│   ├── VialRecord.swift               # struct: value, row, col, centerX, centerY, boundingRect
│   ├── ScanSession.swift              # @Model (SwiftData): id, timestamp, vialCount, csvData, thumbnailData
│   └── ScanResult.swift               # transient result: [VialRecord], annotatedImage: UIImage
│
├── Services/
│   ├── DataMatrixScanService.swift    # decode(image: UIImage) async throws -> ScanResult
│   ├── GridInferenceService.swift     # inferGrid(records: [RawDetection], tolerance: CGFloat) -> [VialRecord]
│   ├── AnnotationRenderer.swift       # render(image: UIImage, records: [VialRecord]) -> UIImage
│   └── CSVExporter.swift              # export(records: [VialRecord]) -> String
│
├── ViewModels/
│   ├── ScanViewModel.swift            # manages scan lifecycle, publishes ScanResult
│   └── HistoryViewModel.swift         # manages persisted sessions
│
└── Views/
    ├── HomeView.swift                  # entry screen: "Scan New Box" + history list
    ├── CameraView.swift               # UIViewControllerRepresentable wrapping AVCaptureSession
    ├── ScanResultView.swift           # tabs: annotated image view + results table
    ├── AnnotatedImageView.swift       # zoomable UIScrollView displaying annotated image
    ├── ResultsTableView.swift         # List of VialRecord rows
    ├── SessionHistoryView.swift       # list of past ScanSessions
    └── SettingsView.swift             # tolerance config, grid size hints
```

### Data Flow

```
User taps "Scan"
  → CameraView / PhotosPicker acquires UIImage
  → ScanViewModel.scan(image:) called
    → DataMatrixScanService.decode(image:)        [background Task]
        → preprocess: grayscale + optional downsample
        → VNDetectBarcodesRequest (DataMatrix symbology)
        → collect RawDetections (value + boundingBox)
    → GridInferenceService.inferGrid(...)          [pure, synchronous]
        → cluster by Y (rows), cluster by X (cols)
        → sort row-major
    → AnnotationRenderer.render(...)               [background]
        → UIGraphicsImageRenderer: draw rects + labels
    → returns ScanResult { records, annotatedImage }
  → ScanViewModel publishes result → ScanResultView updates
  → User exports CSV or saves annotated image
  → ScanSession persisted via SwiftData
```

---

## Detailed Service Specifications

### `DataMatrixScanService`

```swift
struct DataMatrixScanService {
    /// Decodes all DataMatrix codes in the given image.
    ///
    /// Pipeline:
    ///   1. orientationBaked(image:maxDimension:) — UIGraphicsImageRenderer bakes EXIF
    ///      orientation + optional downsample → always .up CGImage. No CIFilter applied.
    ///   2. Full-image Vision scan (VNDetectBarcodesRequest, .dataMatrix, orientation: .up).
    ///   3. If zero results: tiled scan — 3×3 grid, 25% overlap, tile coords mapped back
    ///      to full-image pixel space.
    ///   4. Deduplicate: same value + centers within 60px → keep first occurrence.
    func decode(
        image: UIImage,
        maxDimension: CGFloat = 4000
    ) async throws -> [RawDetection]
}

struct RawDetection {
    let value: String        // decoded payload (ASCII or hex fallback)
    let boundingRect: CGRect // pixel coordinates, UIKit top-left origin
    var center: CGPoint      // = CGPoint(x: boundingRect.midX, y: boundingRect.midY)
}
```

**Critical orientation note:** `CIImage(image:)` incorporates `UIImage.imageOrientation` as an affine transform on the CIImage's coordinate space. If the resulting `CGImage` is then re-tagged with the original orientation (e.g. `UIImage(cgImage: cgOut, orientation: image.imageOrientation)`), the rotation is applied twice. Always use `UIGraphicsImageRenderer` as the **first** preprocessing step to bake orientation into pixels in a single correct pass before applying any `CIFilter`.

**Vision coordinate note:** Vision returns bounding boxes in normalized coordinates with **origin at bottom-left**. These must be converted to UIKit coordinates (origin top-left) before storing in `RawDetection`. Use:
```swift
let flippedY = 1.0 - observation.boundingBox.origin.y - observation.boundingBox.height
```

### `GridInferenceService`

```swift
struct GridInferenceService {
    /// Groups raw detections into a sorted row/column grid.
    /// - tolerance: max pixel distance between centers to be considered same row/col
    func inferGrid(
        detections: [RawDetection],
        tolerance: CGFloat = 100
    ) -> [VialRecord]
}
```

Implementation notes:
- Cluster Y-centers: sort all detections by Y, walk through, assign same row index when consecutive Y values differ by less than `tolerance`.
- Cluster X-centers within each row: sort by X, assign column index similarly.
- This mirrors the Python script's `df['row'] = (df['y'] // TOLERANCE).astype(int)` logic, but a sort-based clustering approach is more robust for iOS where pixel density and image scale vary.

### `AnnotationRenderer`

```swift
struct AnnotationRenderer {
    func render(
        image: UIImage,
        records: [VialRecord],
        boxColor: UIColor = .green,
        labelColor: UIColor = .red,
        lineWidth: CGFloat = 2.0,
        fontSize: CGFloat = 14.0
    ) -> UIImage
}
```

- Draw green rectangle around each vial's bounding box.
- Draw label `"\(index + 1): \(record.value)"` above the bounding box.
- Returns a new `UIImage` (does not mutate input).

### `CSVExporter`

```swift
struct CSVExporter {
    /// Returns CSV string with header: value,x,y,rect,row,col
    /// The rect column is formatted as "(originX, originY, width, height)" — a quoted string.
    /// Width/height may be negative when Vision's bounding box origin is not top-left.
    func export(records: [VialRecord]) -> String

    /// Writes CSV to a temp file URL for sharing via UIActivityViewController
    func exportToTemporaryFile(records: [VialRecord], filename: String) throws -> URL
}
```

---

## UI Screens

### Screen 1: Home / History
- Large "Scan New Box" button (camera icon, prominent CTA).
- Scrollable list of past scan sessions showing: date, vial count, thumbnail.
- Navigation to Settings.

### Screen 2: Camera / Image Picker
- Full-screen camera viewfinder.
- Square framing guide overlay to help user center the vial box.
- "Capture" shutter button.
- "Import from Photos" secondary button.
- Cancel button.

### Screen 3: Processing
- Full-screen modal with spinner and status text:
  - "Preprocessing image…"
  - "Detecting DataMatrix codes…"
  - "Inferring grid positions…"
  - "Rendering annotations…"

### Screen 4: Scan Results
- Two-tab layout:
  - **Tab 1 — Image:** Zoomable annotated image with green overlays and red labels.
  - **Tab 2 — Table:** List of vials in row-major order: `#index | Row X | Col Y | Value`
- Toolbar buttons:
  - "Export CSV" → share sheet
  - "Save Image" → save annotated image to photo library
  - "Rescan" → return to camera
- Summary banner: "Detected N vials"

### Screen 5: Session Detail (from History)
- Same layout as Screen 4 (image + table), but loaded from persisted `ScanSession`.
- Export/save options available.
- "Delete Session" destructive button.

### Screen 6: Settings
- **Grid Tolerance** — stepper/slider, range 50–300, default 100. Explanation: "Adjust if row/column grouping is incorrect."
- **Max Image Dimension** — picker (2000, 4000, 8000), default 4000. Explanation: "Reduce if detection is slow on large images."
- **About** — app version, link to documentation.

---

## Info.plist Requirements

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | "Used to photograph vial rack caps for DataMatrix scanning." |
| `NSPhotoLibraryUsageDescription` | "Used to import existing photos of vial racks." |
| `NSPhotoLibraryAddUsageDescription` | "Used to save annotated scan images to your photo library." |

---

## Xcode Project Setup

- **Bundle Identifier:** `com.yourorg.vialscanner` (replace as appropriate)
- **Deployment Target:** iOS 16.0
- **Swift Package Dependencies:** None required (all native frameworks)
- **Frameworks to link:**
  - `Vision.framework`
  - `AVFoundation.framework`
  - `CoreImage.framework`
  - `CoreGraphics.framework`
  - `PhotosUI.framework`
  - `SwiftData.framework` (iOS 17+) or `CoreData.framework` (iOS 16)
- **Capabilities:** none beyond standard (no push notifications, no iCloud required)

---

## Testing Requirements

### Unit Tests (XCTest)

| Test | Target |
|------|--------|
| `GridInferenceTests` | `GridInferenceService.inferGrid()` with mock detections for 9×9, 8×8, partially-filled grids |
| `CSVExporterTests` | Correct header (`value,x,y,rect,row,col`), correct row count, correct escaping for values with commas |
| `RawDetectionTests` | Vision coordinate flip calculation correctness |
| `AnnotationRendererTests` | Rendered UIImage is non-nil and same size as input |

### Integration Tests — Reference Image Suite

Integration tests live in `ScanPipelineIntegrationTests.swift` (target: `lab-code-readerTests`). They run the real Vision pipeline end-to-end against committed reference files and must be added to the test target's **Copy Bundle Resources** build phase in Xcode.

**Reference files** (at `lab-code-reader/`):

| File | Description |
|------|-------------|
| `input.jpg` | Real photograph of a partially-filled cryovial storage box, iPhone camera, portrait orientation. Contains ~44 DataMatrix codes of varying tilt and contrast. Used as the primary regression image. |
| `output.csv` | Expected decode output for `input.jpg`, schema `value,x,y,rect,row,col`, produced by the reference Python pipeline (`pylibdmtx` + OpenCV). Used to validate detected values and CSV format. |
| `output.jpg` | Annotated reference image showing green bounding boxes and red labels for each detected code. Used as a visual reference only — pixel-perfect match is **not** required by automated tests. |

**Integration test cases** (`ScanPipelineIntegrationTests`):

| Test | Assertion |
|------|-----------|
| `testPipeline_inputJPG_detectsExpectedValues` | ≥ 80% of values in `output.csv` are present in the decoded result |
| `testPipeline_inputJPG_csvSchemaIsCorrect` | Exported CSV header is `value,x,y,rect,row,col`; row count matches record count |
| `testPipeline_inputJPG_gridIndicesAreValid` | All `row`/`col` values are ≥ 0; no two records share the same grid position |

The 80% threshold accounts for codes that may be partially occluded, out-of-focus, or at extreme angles in the reference image. A pass rate below 80% indicates a regression in preprocessing or Vision configuration.

### Manual QA Checklist

- [ ] Camera capture produces a usable `UIImage` with correct orientation.
- [ ] A 9×9 rack with all 81 vials visible is fully decoded.
- [ ] Grid positions are correctly assigned (no off-by-one in rows/cols).
- [ ] CSV export opens correctly in Numbers/Excel with `value,x,y,rect,row,col` columns.
- [ ] Annotated image saves to photo library successfully.
- [ ] Past sessions persist across app restarts.
- [ ] Changing tolerance in Settings affects subsequent scans.
- [ ] "No codes detected" state is handled gracefully without crash.
- [ ] Upload via photo library ("Upload Image" button) produces the same results as camera capture for the same image.

---

## Visual Design — Color Palette

All UI components must reference these named colors via the `Color+AppColors.swift` extension (e.g., `Color.appBlue`). Color assets are defined in `Assets.xcassets` to support future dark-mode variants.

| Token | Hex | Intended Use |
|---|---|---|
| `appBlue` | `#207dbb` | Primary CTA buttons, slider tint, active states |
| `appPurple` | `#775f9a` | Accent / secondary interactive elements |
| `appOrange` | `#ea6d29` | Warnings, caution states |
| `appYellow` | `#edb837` | Badges, status chips |
| `appGreen` | `#1f9591` | Success states, confirmed detection |
| `appRed` | `#a6213b` | Errors, EMPTY placeholder labels, destructive actions |
| `appLightBlue` | `#67bddf` | Selection highlight, secondary accent |
| `appLightTeal` | `#e6f4ef` | Card / surface backgrounds |
| `appGray` | `#6d6e71` | Secondary text, disabled button backgrounds |
| `appLightestBlue` | `#e4f1fb` | Controls panel / header backgrounds |

---

## Future / Out-of-Scope for v1

The following are noted for future versions and should **not** be built in v1:

- Live video scanning (real-time DataMatrix detection from camera feed).
- Manual correction UI (tapping a vial to manually enter its value).
- Cloud sync or remote database upload.
- Rack template configuration (user-defined grid dimensions).
- Multiple rack box types beyond square grids.
- Barcode symbologies other than DataMatrix.

---

## Reference: Python Script Mapping

| Python (original) | iOS equivalent |
|---|---|
| `pylibdmtx.decode(img_gray)` | `VNDetectBarcodesRequest` with `.dataMatrix` symbology |
| `Image.open().convert("RGB")` | `UIImage` → `CIImage` → grayscale via `CIFilter` |
| `img.resize()` using `LANCZOS` | `UIGraphicsImageRenderer` downscale or `CIImage.transformed` |
| `d.rect.left/top/width/height` + scale-back | `VNBarcodeObservation.boundingBox` normalized → pixel rect |
| `y_corrected = height - (y + h)` (flip) | Vision bottom-left origin → UIKit top-left: `flippedY = 1 - y - h` |
| `df['row'] = df['y'] // TOLERANCE` | Sort-based Y-clustering with tolerance threshold |
| `df.sort_values(by=["row","col"])` | `records.sorted { ($0.row, $0.col) < ($1.row, $1.col) }` |
| `cv2.rectangle` + `cv2.putText` | `UIGraphicsImageRenderer` + `UIBezierPath` + `NSAttributedString.draw` |
| `df.to_csv(OUTPUT_CSV)` | `CSVExporter.exportToTemporaryFile` + `UIActivityViewController` |
| `pandas.DataFrame` | `[VialRecord]` (Swift array of structs) |
| `TOLERANCE = 100` config constant | User-configurable setting (default 100) |
| `MAX_DIM = 100000` config constant | `maxDimension: CGFloat = 4000` in service (tighter for mobile) |
