// Views/ScanResultView.swift
import SwiftUI
import SwiftData

struct ScanResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let result: ScanResult

    @State private var selectedRecord: VialRecord?
    @State private var selectedTab = 0
    @State private var showShareSheet = false
    @State private var csvURL: URL?
    @State private var sessionSaved = false
    @State private var historyVM = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Summary banner
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Detected \(result.records.count) vial\(result.records.count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Color.appGreen)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.appLightTeal)

            TabView(selection: $selectedTab) {
                AnnotatedImageView(image: result.annotatedImage, selectedRecord: selectedRecord)
                    .ignoresSafeArea(edges: .bottom)
                    .tabItem { Label("Image", systemImage: "photo") }
                    .tag(0)

                ResultsTableView(records: result.records, selectedRecord: $selectedRecord)
                    .tabItem { Label("Table", systemImage: "tablecells") }
                    .tag(1)
            }
        }
        .navigationTitle("Scan Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Rescan") { dismiss() }
                    .foregroundStyle(Color.appBlue)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { exportCSV() } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    Button { saveImage() } label: {
                        Label("Save Image", systemImage: "photo.badge.arrow.down")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.appBlue)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = csvURL {
                ShareSheet(activityItems: [url])
            }
        }
        .onAppear {
            guard !sessionSaved else { return }
            historyVM.save(result: result, context: modelContext)
            sessionSaved = true
        }
    }

    private func exportCSV() {
        let filename = "scan_\(Int(Date().timeIntervalSince1970)).csv"
        if let url = try? CSVExporter().exportToTemporaryFile(records: result.records, filename: filename) {
            csvURL = url
            showShareSheet = true
        }
    }

    private func saveImage() {
        UIImageWriteToSavedPhotosAlbum(result.annotatedImage, nil, nil, nil)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
