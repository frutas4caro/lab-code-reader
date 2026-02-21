// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("tolerance") private var tolerance: Double = 100
    @AppStorage("maxDimension") private var maxDimension: Double = 4000

    var body: some View {
        Form {
            Section("Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Row Tolerance")
                        Spacer()
                        Text("\(Int(tolerance)) px")
                            .foregroundStyle(Color.appGray)
                    }
                    Slider(value: $tolerance, in: 50...300, step: 10)
                        .tint(Color.appBlue)
                }

                Picker("Max Dimension", selection: $maxDimension) {
                    Text("2000 px").tag(2000.0)
                    Text("4000 px").tag(4000.0)
                    Text("8000 px").tag(8000.0)
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(Color.appGray)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
