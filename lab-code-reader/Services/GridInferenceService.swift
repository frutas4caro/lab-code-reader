// Services/GridInferenceService.swift
import CoreGraphics

/// Assigns row/column grid positions to pixel-space barcode detections.
/// Direct port of the runClustering() algorithm, adapted for pixel CGFloat coords.
/// Rows and columns are 0-indexed per spec (FR-3.5/3.6).
struct GridInferenceService {

    /// - Parameters:
    ///   - detections: Unordered raw detections in pixel space.
    ///   - tolerance: Max Y-distance (pixels) between codes in the same row band.
    func inferGrid(detections: [RawDetection], tolerance: CGFloat) -> [VialRecord] {
        guard !detections.isEmpty else { return [] }

        // 1. Sort top-to-bottom by Y center
        let sortedByY = detections.sorted { $0.center.y < $1.center.y }

        // 2. Row-band partitioning using running average Y
        var clusteredRows: [[RawDetection]] = []
        var currentRow: [RawDetection] = []
        var rowAverageY: CGFloat = 0

        for detection in sortedByY {
            if currentRow.isEmpty {
                currentRow.append(detection)
                rowAverageY = detection.center.y
            } else if abs(detection.center.y - rowAverageY) <= tolerance {
                currentRow.append(detection)
                let totalY = currentRow.reduce(CGFloat(0)) { $0 + $1.center.y }
                rowAverageY = totalY / CGFloat(currentRow.count)
            } else {
                clusteredRows.append(currentRow)
                currentRow = [detection]
                rowAverageY = detection.center.y
            }
        }
        if !currentRow.isEmpty { clusteredRows.append(currentRow) }

        // 3. Sort within each row by X, assign 0-indexed row/col
        var records: [VialRecord] = []
        for (rowIndex, row) in clusteredRows.enumerated() {
            for (colIndex, detection) in row.sorted(by: { $0.center.x < $1.center.x }).enumerated() {
                records.append(VialRecord(
                    value: detection.value,
                    row: rowIndex,
                    col: colIndex,
                    centerX: detection.center.x,
                    centerY: detection.center.y,
                    boundingRect: detection.boundingRect
                ))
            }
        }
        return records
    }
}
