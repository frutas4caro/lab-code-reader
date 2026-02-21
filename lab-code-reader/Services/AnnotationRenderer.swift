// Services/AnnotationRenderer.swift
import UIKit

/// Renders circle annotations and value labels onto a UIImage for each detected vial.
/// Each DataMatrix code is circled; the decoded value is printed above the circle.
struct AnnotationRenderer {

    func render(
        image: UIImage,
        records: [VialRecord],
        circleColor: UIColor = UIColor(red: 0.122, green: 0.584, blue: 0.569, alpha: 1.0), // appGreen
        labelColor: UIColor  = UIColor(red: 0.651, green: 0.129, blue: 0.231, alpha: 1.0), // appRed
        lineWidth: CGFloat   = 2.5,
        fontSize: CGFloat    = 11.0
    ) -> UIImage {
        // Use scale=1.0 so we draw in pixel space, matching the coordinate space of
        // the boundingRect values stored in VialRecord (which are in pixel coordinates
        // from the DataMatrixScanService's normalised CGImage).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)

            for (index, record) in records.enumerated() {
                let rect = record.boundingRect

                // Circle centred on the code, radius = half the longest side + padding.
                // Using the longest side handles non-square bounding rects (common when
                // Vision returns slightly rotated bounding boxes with negative dimensions).
                let halfW = abs(rect.width)  / 2
                let halfH = abs(rect.height) / 2
                let radius = max(halfW, halfH) + 8
                let center = CGPoint(x: rect.midX, y: rect.midY)

                let circlePath = UIBezierPath(
                    arcCenter: center,
                    radius: radius,
                    startAngle: 0,
                    endAngle: 2 * .pi,
                    clockwise: true
                )
                circlePath.lineWidth = lineWidth
                circleColor.setStroke()
                circlePath.stroke()

                // Label: sequential index + decoded value, drawn above the circle.
                let label = "\(index + 1): \(record.value)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: labelColor
                ]
                let labelSize = NSAttributedString(string: label, attributes: attrs).size()
                let labelOrigin = CGPoint(
                    x: center.x - labelSize.width / 2,
                    y: center.y - radius - labelSize.height - 3
                )
                NSAttributedString(string: label, attributes: attrs).draw(at: labelOrigin)
            }
        }
    }
}
