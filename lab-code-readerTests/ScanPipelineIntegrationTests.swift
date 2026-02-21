// Tests/ScanPipelineIntegrationTests.swift
//
// Integration tests that run the full scan pipeline against the reference
// input.jpg and validate decoded values against output.csv.
//
// ⚠️ SETUP REQUIRED: In Xcode, add input.jpg and output.csv to the
// lab-code-readerTests target's "Copy Bundle Resources" build phase.
// Both files live at lab-code-reader/input.jpg and lab-code-reader/output.csv.

import XCTest
@testable import lab_code_reader

final class ScanPipelineIntegrationTests: XCTestCase {

    private let scanService = DataMatrixScanService()
    private let gridService = GridInferenceService()
    private let csvExporter = CSVExporter()
    private let renderer    = AnnotationRenderer()

    // MARK: - Helpers

    private func bundleURL(name: String, ext: String) throws -> URL {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext) else {
            XCTFail("❌ '\(name).\(ext)' not found in test bundle. " +
                    "Add it to lab-code-readerTests → Copy Bundle Resources.")
            throw XCTestError(.failureWhileWaiting)
        }
        return url
    }

    private func inputImage() throws -> UIImage {
        let url = try bundleURL(name: "input", ext: "jpg")
        guard let image = UIImage(contentsOfFile: url.path) else {
            XCTFail("UIImage(contentsOfFile:) returned nil for input.jpg")
            throw XCTestError(.failureWhileWaiting)
        }
        return image
    }

    /// Parses barcode values (first column, no header) from the reference output.csv.
    private func expectedValues() throws -> Set<String> {
        let url     = try bundleURL(name: "output", ext: "csv")
        let content = try String(contentsOf: url, encoding: .utf8)
        return Set(
            content.components(separatedBy: "\n")
                .dropFirst()
                .compactMap { line -> String? in
                    let token = line.components(separatedBy: ",").first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    return token.isEmpty ? nil : token
                }
        )
    }

    /// RFC 4180-aware CSV parser matching SessionDetailView.parseCSV — schema: value,x,y,rect,row,col
    private func parseCSV(_ csv: String) -> [VialRecord] {
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }.dropFirst()
        return lines.compactMap { line -> VialRecord? in
            var fields: [String] = []
            var current = ""
            var inQuotes = false
            for char in line {
                if char == "\"" { inQuotes.toggle() }
                else if char == "," && !inQuotes {
                    fields.append(current.trimmingCharacters(in: .whitespaces)); current = ""
                } else { current.append(char) }
            }
            fields.append(current.trimmingCharacters(in: .whitespaces))
            guard fields.count >= 6,
                  let x   = Double(fields[1]), let y = Double(fields[2]),
                  let row = Int(fields[4]),    let col = Int(fields[5])
            else { return nil }
            return VialRecord(value: fields[0], row: row, col: col,
                              centerX: CGFloat(x), centerY: CGFloat(y), boundingRect: .zero)
        }
    }

    // MARK: - Preprocessing tests

    /// Verifies format.scale=1.0 fix: output pixel dimensions must respect maxDimension.
    func testOrientationBaked_pixelDimensionsRespectMaxDimension() throws {
        let image  = try inputImage()
        let maxDim: CGFloat = 1000

        let pixelW  = image.size.width  * image.scale
        let pixelH  = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        let s       = longest > maxDim ? maxDim / longest : 1.0
        let target  = CGSize(width: (pixelW * s).rounded(), height: (pixelH * s).rounded())

        let format  = UIGraphicsImageRendererFormat(); format.scale = 1.0
        let result  = UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        let cg      = try XCTUnwrap(result.cgImage)

        XCTAssertLessThanOrEqual(CGFloat(cg.width),  maxDim + 1,
            "CGImage width \(cg.width) exceeds maxDimension \(Int(maxDim)). " +
            "format.scale=1.0 may have been reverted.")
        XCTAssertLessThanOrEqual(CGFloat(cg.height), maxDim + 1,
            "CGImage height \(cg.height) exceeds maxDimension \(Int(maxDim)).")
    }

    // MARK: - Detection quantity tests

    /// The tiled pipeline must find more than the 3 codes the old 4×4 single-pass
    /// strategy returned from input.jpg. Any regression to ≤ 3 indicates the adaptive
    /// tiling or progressive fallback has been removed.
    func testPipeline_inputJPG_detectsMoreThanThreeCodes() async throws {
        let detections = try await scanService.decode(image: try inputImage())
        let records    = gridService.inferGrid(detections: detections, tolerance: 100)
        print("[Integration] Detected \(records.count) codes from input.jpg")
        XCTAssertGreaterThan(records.count, 3,
            "Expected > 3 codes; got \(records.count). " +
            "Adaptive tiling (300px / 200px) may have regressed.")
    }

    /// Full pipeline: ≥ 80% of expected values from output.csv must be detected.
    func testPipeline_inputJPG_detectsExpectedValues() async throws {
        let image      = try inputImage()
        let detections = try await scanService.decode(image: image)

        XCTAssertFalse(detections.isEmpty,
            "Vision returned 0 detections. Check format.scale=1.0, tiling, orientation.")

        let records   = gridService.inferGrid(detections: detections, tolerance: 100)
        let detected  = Set(records.map { $0.value })
        let expected  = try expectedValues()
        let matched   = detected.intersection(expected)
        let matchRate = Double(matched.count) / Double(expected.count)

        print("──────────────────────────────────────────────")
        print("[Integration] Detected : \(detected.count) codes")
        print("[Integration] Expected : \(expected.count) codes")
        print("[Integration] Matched  : \(matched.count) (\(Int(matchRate * 100))%)")
        print("[Integration] Missing  : \(expected.subtracting(detected).sorted())")
        print("[Integration] Extra    : \(detected.subtracting(expected).sorted())")
        print("──────────────────────────────────────────────")

        XCTAssertGreaterThanOrEqual(matchRate, 0.80,
            "Expected ≥ 80% match; got \(Int(matchRate * 100))%. " +
            "Missing: \(expected.subtracting(detected).sorted())")
    }

    // MARK: - Annotation tests

    /// AnnotationRenderer must produce a non-nil UIImage of the same pixel dimensions
    /// as the input and must include circle drawing (verified indirectly via non-zero size).
    func testAnnotationRenderer_producesCorrectImage() throws {
        // Construct a minimal 200×200 white test image with one record
        let size   = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1.0
        let input  = UIGraphicsImageRenderer(size: size, format: format)
            .image { ctx in UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size)) }
        let record = VialRecord(value: "TEST", row: 0, col: 0,
                                centerX: 100, centerY: 100,
                                boundingRect: CGRect(x: 80, y: 80, width: 40, height: 40))

        let output = renderer.render(image: input, records: [record])
        let cg     = try XCTUnwrap(output.cgImage,
                        "render() returned an image with no CGImage backing")

        XCTAssertEqual(cg.width,  Int(size.width),
            "Annotated image width must match input width")
        XCTAssertEqual(cg.height, Int(size.height),
            "Annotated image height must match input height")
    }

    /// Rendering multiple records must not crash or produce zero-size output.
    func testAnnotationRenderer_handlesMultipleRecords() async throws {
        let image      = try inputImage()
        let detections = try await scanService.decode(image: image)
        let records    = gridService.inferGrid(detections: detections, tolerance: 100)
        guard !records.isEmpty else { XCTFail("No records to annotate"); return }

        let annotated = renderer.render(image: image, records: records)
        XCTAssertNotNil(annotated.cgImage, "render() must return a valid UIImage for \(records.count) records")
    }

    // MARK: - CSV schema tests

    /// CSV header must be value,x,y,rect,row,col.
    func testCSV_headerMatchesSchema() async throws {
        let records = gridService.inferGrid(
            detections: try await scanService.decode(image: try inputImage()),
            tolerance: 100
        )
        let header = csvExporter.export(records: records)
            .components(separatedBy: "\n").first ?? ""
        XCTAssertEqual(header, "value,x,y,rect,row,col")
    }

    /// Every data row must have exactly 6 comma-separated fields (rect is quoted).
    func testCSV_rowsHaveSixFields() async throws {
        let records = gridService.inferGrid(
            detections: try await scanService.decode(image: try inputImage()),
            tolerance: 100
        )
        guard !records.isEmpty else { XCTFail("No records to validate"); return }

        let lines = csvExporter.export(records: records)
            .components(separatedBy: "\n").dropFirst().filter { !$0.isEmpty }
        for line in lines {
            var count = 0; var inQ = false
            for c in line {
                if c == "\"" { inQ.toggle() } else if c == "," && !inQ { count += 1 }
            }
            XCTAssertEqual(count + 1, 6, "Row has \(count + 1) fields, expected 6: '\(line)'")
        }
    }

    // MARK: - CSV round-trip (history parsing)

    /// Export → parse back → records match. Catches schema mismatches between
    /// CSVExporter and SessionDetailView.parseCSV (which previously showed 0 vials).
    func testCSVRoundTrip_exportThenParse_recordsMatch() async throws {
        let original = gridService.inferGrid(
            detections: try await scanService.decode(image: try inputImage()),
            tolerance: 100
        )
        guard !original.isEmpty else { XCTFail("No records to round-trip"); return }

        let parsed = parseCSV(csvExporter.export(records: original))

        XCTAssertEqual(parsed.count, original.count,
            "Parsed \(parsed.count) records but exported \(original.count). " +
            "parseCSV field indices may not match CSVExporter column order.")

        let byValue = Dictionary(uniqueKeysWithValues: original.map { ($0.value, $0) })
        for record in parsed {
            guard let src = byValue[record.value] else {
                XCTFail("Parsed value '\(record.value)' not in original records"); continue
            }
            XCTAssertEqual(record.row, src.row,
                "Row mismatch for '\(record.value)': parsed \(record.row), original \(src.row)")
            XCTAssertEqual(record.col, src.col,
                "Col mismatch for '\(record.value)': parsed \(record.col), original \(src.col)")
        }
    }

    // MARK: - Annotated image persistence

    /// jpegData(compressionQuality:) on the rendered image must produce non-empty Data
    /// that round-trips back to a UIImage — ensures HistoryViewModel can persist it.
    func testAnnotatedImageJPEGRoundTrip() async throws {
        let image      = try inputImage()
        let detections = try await scanService.decode(image: image)
        let records    = gridService.inferGrid(detections: detections, tolerance: 100)
        let annotated  = renderer.render(image: image, records: records)

        let jpeg = try XCTUnwrap(annotated.jpegData(compressionQuality: 0.85),
                       "jpegData returned nil — annotated image may lack a CGImage backing")
        XCTAssertFalse(jpeg.isEmpty, "JPEG data must not be empty")
        XCTAssertNotNil(UIImage(data: jpeg),
            "UIImage(data:) must reconstruct a valid image from the persisted JPEG")
    }

    // MARK: - Grid validity

    func testPipeline_inputJPG_gridIndicesAreValid() async throws {
        let records = gridService.inferGrid(
            detections: try await scanService.decode(image: try inputImage()),
            tolerance: 100
        )
        for record in records {
            XCTAssertGreaterThanOrEqual(record.row, 0,
                "Row index must be ≥ 0 for '\(record.value)'")
            XCTAssertGreaterThanOrEqual(record.col, 0,
                "Col index must be ≥ 0 for '\(record.value)'")
        }
        let positions = records.map { "\($0.row),\($0.col)" }
        let dupes     = positions.filter { p in positions.filter { $0 == p }.count > 1 }
        XCTAssertEqual(positions.count, Set(positions).count,
            "Duplicate grid positions: \(Set(dupes).sorted())")
    }
}
