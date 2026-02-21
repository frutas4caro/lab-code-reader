// Views/AnnotatedImageView.swift
import SwiftUI
import UIKit

/// Pinch-to-zoom image viewer. Scrolls to selectedRecord's bounding rect when changed.
struct AnnotatedImageView: UIViewRepresentable {
    let image: UIImage
    var selectedRecord: VialRecord?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        let scrollSize = scrollView.bounds.size
        guard scrollSize.width > 0, scrollSize.height > 0 else { return }

        // Fit image proportionally into the scroll view
        let widthScale = scrollSize.width / image.size.width
        let heightScale = scrollSize.height / image.size.height
        let fitScale = min(widthScale, heightScale)
        let fittedSize = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)

        imageView.frame = CGRect(
            x: max(0, (scrollSize.width - fittedSize.width) / 2),
            y: max(0, (scrollSize.height - fittedSize.height) / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
        scrollView.contentSize = CGSize(
            width: max(scrollSize.width, fittedSize.width),
            height: max(scrollSize.height, fittedSize.height)
        )

        // Scroll to the selected record's bounding rect
        if let record = selectedRecord {
            let scaleX = fittedSize.width / image.size.width
            let scaleY = fittedSize.height / image.size.height
            let highlight = CGRect(
                x: record.boundingRect.minX * scaleX + imageView.frame.minX,
                y: record.boundingRect.minY * scaleY + imageView.frame.minY,
                width: record.boundingRect.width * scaleX,
                height: record.boundingRect.height * scaleY
            )
            scrollView.scrollRectToVisible(highlight.insetBy(dx: -40, dy: -40), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
