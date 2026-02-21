// Models/VialRecord.swift
import Foundation
import CoreGraphics

/// A single detected DataMatrix barcode mapped to its grid position.
/// Coordinates are in pixel space (UIKit top-left origin).
struct VialRecord: Identifiable, Equatable {
    let id = UUID()
    let value: String
    let row: Int        // 0-indexed row in the storage box grid
    let col: Int        // 0-indexed column in the storage box grid
    let centerX: CGFloat
    let centerY: CGFloat
    let boundingRect: CGRect  // pixel coords, UIKit top-left origin
}
