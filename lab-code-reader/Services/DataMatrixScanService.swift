// Services/DataMatrixScanService.swift
import UIKit
import Vision

/// Raw detection output from Vision — pixel coords, UIKit top-left origin.
struct RawDetection {
    let value: String
    let boundingRect: CGRect
    var center: CGPoint
}

/// Wraps VNDetectBarcodesRequest to decode DataMatrix codes from a UIImage.
///
/// Detection pipeline:
///   1. orientationBaked() — UIGraphicsImageRenderer with format.scale=1.0 bakes EXIF
///      orientation and applies the maxDimension cap in pixel space (not UIKit points).
///   2. Full-image Vision scan (fast, catches large/clear codes immediately).
///   3. If < 5 codes: adaptive 300px tiled scan — targets tile widths of ~300px so that
///      codes ≥ 20px represent ≥ 8% of tile width, inside Vision's reliable range.
///   4. If < 10 codes: finer 200px tiled scan — catches codes down to ~15px.
///      All tiles within a pass run concurrently via TaskGroup.
///   5. Deduplicate by value + 60px centre proximity across all passes.
struct DataMatrixScanService {

    enum ScanError: Error, LocalizedError {
        case invalidImage
        var errorDescription: String? { "Could not convert image for Vision processing." }
    }

    func decode(image: UIImage, maxDimension: CGFloat = 4000) async throws -> [RawDetection] {
        let normalized = orientationBaked(image: image, maxDimension: maxDimension)
        guard let cgImage = normalized.cgImage else { throw ScanError.invalidImage }
        let fullSize = CGSize(width: cgImage.width, height: cgImage.height)

        print("[DataMatrixScanService] Image ready for Vision: \(Int(fullSize.width))×\(Int(fullSize.height))px")

        // Pass 1: full image (cheap; catches large/prominent codes without tiling)
        var results = try await visionScan(crop: cgImage, tileOrigin: .zero, fullSize: fullSize)
        log(results, pass: "full-image")

        // Pass 2: adaptive tiled scan, ~300px target tiles
        if results.count < 5 {
            let (c, r) = adaptiveGrid(for: fullSize, targetTileSize: 300)
            let pass2 = try await tiledScan(cgImage: cgImage, fullSize: fullSize,
                                            gridCols: c, gridRows: r, overlap: 0.25)
            results = deduplicated(results + pass2)
            log(results, pass: "\(c)×\(r) adaptive (300px)")
        }

        // Pass 3: finer tiled scan, ~200px target tiles — rescues very small codes (<30px)
        if results.count < 10 {
            let (c, r) = adaptiveGrid(for: fullSize, targetTileSize: 200)
            let pass3 = try await tiledScan(cgImage: cgImage, fullSize: fullSize,
                                            gridCols: c, gridRows: r, overlap: 0.30)
            results = deduplicated(results + pass3)
            log(results, pass: "\(c)×\(r) fine (200px)")
        }

        return results
    }

    // MARK: - Orientation + resize

    /// Renders through UIGraphicsImageRenderer with format.scale=1.0 so it operates in
    /// pixel space rather than UIKit point space. Without this, image.size (points) can
    /// be less than maxDimension even for large iPhone photos (e.g. 1920 pts on a 3x
    /// device = 5760px), causing the downsample step to be silently skipped.
    private func orientationBaked(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelW = image.size.width  * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        let s = longest > maxDimension ? maxDimension / longest : 1.0
        let targetPixels = CGSize(width:  (pixelW * s).rounded(),
                                  height: (pixelH * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: targetPixels, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetPixels))
        }
    }

    // MARK: - Tiled scan

    /// Returns grid dimensions that target tiles of approximately `targetTileSize` pixels
    /// wide. Capped to avoid excessive Vision calls on large images.
    private func adaptiveGrid(for size: CGSize, targetTileSize: CGFloat) -> (cols: Int, rows: Int) {
        let cols = max(2, min(10, Int(ceil(size.width  / targetTileSize))))
        let rows = max(2, min(14, Int(ceil(size.height / targetTileSize))))
        return (cols, rows)
    }

    private func tiledScan(cgImage: CGImage, fullSize: CGSize,
                            gridCols: Int, gridRows: Int, overlap: CGFloat) async throws -> [RawDetection] {
        let tileW = fullSize.width  / CGFloat(gridCols)
        let tileH = fullSize.height / CGFloat(gridRows)
        let padW  = tileW * overlap
        let padH  = tileH * overlap

        var crops: [(CGImage, CGPoint)] = []
        for row in 0..<gridRows {
            for col in 0..<gridCols {
                let x = max(0, CGFloat(col) * tileW - padW)
                let y = max(0, CGFloat(row) * tileH - padH)
                let w = min(fullSize.width  - x, tileW + 2 * padW)
                let h = min(fullSize.height - y, tileH + 2 * padH)
                if let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) {
                    crops.append((cropped, CGPoint(x: x, y: y)))
                }
            }
        }

        return try await withThrowingTaskGroup(of: [RawDetection].self) { group in
            for (crop, origin) in crops {
                group.addTask { try await self.visionScan(crop: crop, tileOrigin: origin, fullSize: fullSize) }
            }
            var all: [RawDetection] = []
            for try await batch in group { all.append(contentsOf: batch) }
            return all
        }
    }

    // MARK: - Single Vision call

    private func visionScan(crop: CGImage, tileOrigin: CGPoint,
                             fullSize: CGSize) async throws -> [RawDetection] {
        let tileSize = CGSize(width: crop.width, height: crop.height)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let obs = req.results as? [VNBarcodeObservation] ?? []
                let detections: [RawDetection] = obs
                    .filter  { $0.symbology == .dataMatrix }
                    .compactMap { ob -> RawDetection? in
                        guard let value = ob.payloadStringValue else { return nil }
                        let flippedY = 1.0 - ob.boundingBox.origin.y - ob.boundingBox.height
                        let rect = CGRect(
                            x: tileOrigin.x + ob.boundingBox.origin.x * tileSize.width,
                            y: tileOrigin.y + flippedY               * tileSize.height,
                            width:  ob.boundingBox.width  * tileSize.width,
                            height: ob.boundingBox.height * tileSize.height
                        )
                        return RawDetection(value: value, boundingRect: rect,
                                            center: CGPoint(x: rect.midX, y: rect.midY))
                    }
                continuation.resume(returning: detections)
            }
            request.symbologies = [.dataMatrix]
            do {
                try VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
                    .perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Deduplication

    private func deduplicated(_ detections: [RawDetection]) -> [RawDetection] {
        var unique: [RawDetection] = []
        for candidate in detections {
            let isDuplicate = unique.contains { ex in
                ex.value == candidate.value &&
                hypot(ex.center.x - candidate.center.x,
                      ex.center.y - candidate.center.y) < 60
            }
            if !isDuplicate { unique.append(candidate) }
        }
        return unique
    }

    private func log(_ detections: [RawDetection], pass: String) {
        if detections.isEmpty {
            print("[DataMatrixScanService] \(pass) pass: 0 DataMatrix codes found.")
        } else {
            let values = detections.map { $0.value }.joined(separator: ", ")
            print("[DataMatrixScanService] \(pass) pass: \(detections.count) code(s) — \(values)")
        }
    }
}
