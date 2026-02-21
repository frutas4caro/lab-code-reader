// ViewModels/ScanViewModel.swift
import SwiftUI
import Observation

@Observable
final class ScanViewModel {
    var scanResult: ScanResult?
    var isScanning = false
    var statusMessage = ""
    var errorMessage: String?

    // @AppStorage is not directly compatible with @Observable's tracking;
    // use @ObservationIgnored to opt the property wrappers out of macro synthesis.
    @ObservationIgnored
    @AppStorage("tolerance") var tolerance: Double = 100

    @ObservationIgnored
    @AppStorage("maxDimension") var maxDimension: Double = 4000

    private let scanService = DataMatrixScanService()
    private let gridService = GridInferenceService()
    private let renderer = AnnotationRenderer()

    @MainActor
    func scan(image: UIImage) async {
        isScanning = true
        errorMessage = nil

        do {
            statusMessage = "Preprocessing…"
            // Brief yield so SwiftUI can render the status update before heavy work
            try await Task.sleep(nanoseconds: 50_000_000)

            statusMessage = "Detecting DataMatrix codes…"
            let detections = try await scanService.decode(image: image, maxDimension: CGFloat(maxDimension))

            statusMessage = "Inferring grid positions…"
            let records = gridService.inferGrid(detections: detections, tolerance: CGFloat(tolerance))

            statusMessage = "Rendering annotations…"
            let annotated = renderer.render(image: image, records: records)

            scanResult = ScanResult(records: records, annotatedImage: annotated)
        } catch {
            errorMessage = error.localizedDescription
        }

        isScanning = false
        statusMessage = ""
    }
}
