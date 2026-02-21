// Models/ScanSession.swift
import Foundation
import SwiftData

/// Persisted record of a completed scan session.
/// UIImage is not storable in SwiftData directly — images are stored as JPEG Data.
/// annotatedImageData stores the full circle-annotated image for history detail view.
/// thumbnailData stores a 400px-wide compressed preview for the history list row.
@Model
final class ScanSession {
    var id: UUID
    var timestamp: Date
    var vialCount: Int
    var csvData: String
    var thumbnailData: Data
    /// Full-resolution JPEG of the circle-annotated scan image.
    /// Default is Data() so existing SwiftData records without this field migrate cleanly.
    var annotatedImageData: Data = Data()

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        vialCount: Int,
        csvData: String,
        thumbnailData: Data,
        annotatedImageData: Data = Data()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.vialCount = vialCount
        self.csvData = csvData
        self.thumbnailData = thumbnailData
        self.annotatedImageData = annotatedImageData
    }
}
