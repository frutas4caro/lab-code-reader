// Views/ResultsTableView.swift
import SwiftUI

struct ResultsTableView: View {
    let records: [VialRecord]
    @Binding var selectedRecord: VialRecord?

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView(
                "No Codes Detected",
                systemImage: "barcode.viewfinder",
                description: Text("No DataMatrix codes detected. Try improving lighting or image focus.")
            )
            .foregroundStyle(Color.appGray)
        } else {
            List(Array(records.enumerated()), id: \.element.id) { index, record in
                Button {
                    selectedRecord = record
                } label: {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.appGray)
                            .frame(width: 28, alignment: .trailing)

                        Text("R\(record.row)")
                            .font(.caption.bold())
                            .foregroundStyle(Color.appBlue)
                            .frame(width: 36)

                        Text("C\(record.col)")
                            .font(.caption.bold())
                            .foregroundStyle(Color.appPurple)
                            .frame(width: 36)

                        Text(record.value)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(Color.primary)
                    }
                }
                .listRowBackground(
                    selectedRecord?.id == record.id ? Color.appLightestBlue : Color.clear
                )
            }
            .listStyle(.plain)
        }
    }
}
