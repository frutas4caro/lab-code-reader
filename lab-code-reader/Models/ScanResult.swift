// Models/ScanResult.swift
import UIKit

/// Transient result of a single scan pipeline run.
/// The annotatedImage is not persisted — only thumbnailData in ScanSession is stored.
struct ScanResult {
    let records: [VialRecord]
    let annotatedImage: UIImage
}
