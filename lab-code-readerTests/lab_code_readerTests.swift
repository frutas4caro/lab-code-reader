//
//  lab_code_readerTests.swift
//  lab-code-readerTests
//
//  Created by Carolyn Aquino on 11/12/25.
//

import XCTest
@testable import lab_code_reader

final class lab_code_readerTests: XCTestCase {

    // MARK: - GridInferenceService
    func testResourcesExist() {
        let jpgPath = Bundle(for: type(of: self)).path(forResource: "input", ofType: "jpg")
        let csvPath = Bundle(for: type(of: self)).path(forResource: "output", ofType: "csv")
        
        assert(jpgPath != nil, "input.jpg was not found in the test bundle!")
        assert(csvPath != nil, "output.csv was not found in the test bundle!")
    }
    
    func testInferGrid_3x3() {
        // 9 detections laid out in a known 3×3 pixel grid (100px spacing)
        let service = GridInferenceService()
        var detections: [RawDetection] = []
        for r in 0..<3 {
            for c in 0..<3 {
                let x = CGFloat(100 + c * 100)
                let y = CGFloat(100 + r * 100)
                detections.append(RawDetection(
                    value: "R\(r)C\(c)",
                    boundingRect: CGRect(x: x - 10, y: y - 10, width: 20, height: 20),
                    center: CGPoint(x: x, y: y)
                ))
            }
        }
        // Shuffle to verify ordering is robust
        detections.shuffle()

        let records = service.inferGrid(detections: detections, tolerance: 20)

        XCTAssertEqual(records.count, 9, "Expected 9 VialRecords for a 3×3 grid")
        // Verify each record's row/col matches the expected value string
        for record in records {
            let expected = "R\(record.row)C\(record.col)"
            XCTAssertEqual(record.value, expected,
                           "Record at row=\(record.row) col=\(record.col) has value '\(record.value)', expected '\(expected)'")
        }
    }

    // MARK: - CSVExporter

    func testCSVExport_header() {
        let csv = CSVExporter().export(records: [])
        let firstLine = csv.components(separatedBy: "\n").first ?? ""
        XCTAssertEqual(firstLine, "value,x,y,rect,row,col", "CSV header must be 'value,x,y,rect,row,col'")
    }

    func testCSVExport_commaEscaping() {
        let record = VialRecord(value: "A,B", row: 0, col: 0, centerX: 1, centerY: 2, boundingRect: .zero)
        let csv = CSVExporter().export(records: [record])
        XCTAssertTrue(csv.contains("\"A,B\""), "Value containing comma must be double-quoted in CSV output")
    }

    // MARK: - AnnotationRenderer

    func testAnnotationRenderer_nonNil() {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let input = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let output = AnnotationRenderer().render(image: input, records: [])
        XCTAssertNotNil(output, "render(image:records:) must return a non-nil UIImage")
        XCTAssertEqual(output.size, input.size, "Output image must match input image dimensions")
    }
}
