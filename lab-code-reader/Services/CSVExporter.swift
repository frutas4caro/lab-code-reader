// Services/CSVExporter.swift
import Foundation

struct CSVExporter {

    /// Returns a CSV string with header row: value,x,y,rect,row,col
    func export(records: [VialRecord]) -> String {
        var lines = ["value,x,y,rect,row,col"]
        for record in records {
            // RFC 4180: quote any value containing a comma
            let escaped = record.value.contains(",") ? "\"\(record.value)\"" : record.value
            let r = record.boundingRect
            let rectStr = "\"(\(Int(r.origin.x)), \(Int(r.origin.y)), \(Int(r.width)), \(Int(r.height)))\""
            lines.append("\(escaped),\(record.centerX),\(record.centerY),\(rectStr),\(record.row),\(record.col)")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the CSV to a temporary file and returns its URL.
    func exportToTemporaryFile(records: [VialRecord], filename: String) throws -> URL {
        let csv = export(records: records)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
