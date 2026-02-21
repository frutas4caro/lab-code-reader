// ViewModels/HistoryViewModel.swift
import SwiftUI
import SwiftData
import Observation

@Observable
final class HistoryViewModel {
    var sessions: [ScanSession] = []

    func load(context: ModelContext) {
        let descriptor = FetchDescriptor<ScanSession>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        sessions = (try? context.fetch(descriptor)) ?? []
    }

    func save(result: ScanResult, context: ModelContext) {
        let csv       = CSVExporter().export(records: result.records)
        let thumbData = makeThumbnail(from: result.annotatedImage)
        // Persist the full annotated image as JPEG so the history detail view can
        // display it with circles and labels without re-running the scan pipeline.
        let annotatedData = result.annotatedImage.jpegData(compressionQuality: 0.85) ?? Data()
        let session = ScanSession(
            vialCount: result.records.count,
            csvData: csv,
            thumbnailData: thumbData,
            annotatedImageData: annotatedData
        )
        context.insert(session)
        try? context.save()
        load(context: context)
    }

    func delete(session: ScanSession, context: ModelContext) {
        context.delete(session)
        try? context.save()
        load(context: context)
    }

    // MARK: - Private

    private func makeThumbnail(from image: UIImage) -> Data {
        let targetWidth: CGFloat = 400
        let scale = targetWidth / image.size.width
        let newSize = CGSize(width: targetWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return thumb.jpegData(compressionQuality: 0.7) ?? Data()
    }
}
