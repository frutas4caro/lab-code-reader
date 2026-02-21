// Views/SessionHistoryView.swift
import SwiftUI
import SwiftData

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var historyVM = HistoryViewModel()
    @State private var selectedSession: ScanSession?

    var body: some View {
        Group {
            if historyVM.sessions.isEmpty {
                ContentUnavailableView("No Scans Yet", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(Color.appGray)
            } else {
                List {
                    ForEach(historyVM.sessions) { session in
                        Button { selectedSession = session } label: {
                            SessionRowView(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            historyVM.delete(session: historyVM.sessions[index], context: modelContext)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { historyVM.load(context: modelContext) }
        .navigationDestination(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }
}

// MARK: - Row cell

struct SessionRowView: View {
    let session: ScanSession

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = UIImage(data: session.thumbnailData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.appLightTeal
                        .overlay(Image(systemName: "photo").foregroundStyle(Color.appGray))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)

                Text("\(session.vialCount) vials")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.appYellow.opacity(0.2))
                    .foregroundStyle(Color.appYellow)
                    .clipShape(Capsule())
            }

            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.appGray)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session detail (history — annotated image + results table)

struct SessionDetailView: View {
    let session: ScanSession
    @State private var selectedRecord: VialRecord?
    @State private var selectedTab = 0

    var records: [VialRecord] { parseCSV(session.csvData) }

    /// Annotated image stored as JPEG in session. Nil for sessions saved before
    /// annotatedImageData was added (those sessions show a placeholder).
    var annotatedImage: UIImage? {
        session.annotatedImageData.isEmpty ? nil : UIImage(data: session.annotatedImageData)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary banner
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(session.vialCount) vial\(session.vialCount == 1 ? "" : "s") detected")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.appGreen)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.appLightTeal)

            TabView(selection: $selectedTab) {
                Group {
                    if let image = annotatedImage {
                        AnnotatedImageView(image: image, selectedRecord: selectedRecord)
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        ContentUnavailableView(
                            "Image Not Available",
                            systemImage: "photo",
                            description: Text("This session was saved before image persistence was added.")
                        )
                        .foregroundStyle(Color.appGray)
                    }
                }
                .tabItem { Label("Image", systemImage: "photo") }
                .tag(0)

                ResultsTableView(records: records, selectedRecord: $selectedRecord)
                    .tabItem { Label("Table", systemImage: "tablecells") }
                    .tag(1)
            }
        }
        .navigationTitle(session.timestamp.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func parseCSV(_ csv: String) -> [VialRecord] {
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }.dropFirst()
        return lines.compactMap { line -> VialRecord? in
            // RFC 4180-aware split: respect quoted fields (e.g. the rect column)
            var fields: [String] = []
            var current = ""
            var inQuotes = false
            for char in line {
                if char == "\"" { inQuotes.toggle() }
                else if char == "," && !inQuotes { fields.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
                else { current.append(char) }
            }
            fields.append(current.trimmingCharacters(in: .whitespaces))

            // Schema: value, x, y, rect, row, col  (6 columns)
            guard fields.count >= 6,
                  let xDouble = Double(fields[1]),
                  let yDouble = Double(fields[2]),
                  // fields[3] is the rect string — skip it, store .zero
                  let row = Int(fields[4]),
                  let col = Int(fields[5])
            else { return nil }

            return VialRecord(
                value: fields[0],
                row: row,
                col: col,
                centerX: CGFloat(xDouble),
                centerY: CGFloat(yDouble),
                boundingRect: .zero
            )
        }
    }

}
