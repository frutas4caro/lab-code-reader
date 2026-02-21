// Views/HomeView.swift
import SwiftUI
import PhotosUI

struct HomeView: View {
    @State private var scanViewModel = ScanViewModel()
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var navigateToResult = false
    @State private var showSettings = false
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scan trigger button + status area
                VStack(spacing: 12) {
                    // Primary: live camera scan
                    Button {
                        selectedImage = nil
                        showCamera = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.title2)
                            Text("Scan New Box")
                                .font(.title3.bold())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.appBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(scanViewModel.isScanning)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Secondary: upload from photo library
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                            Text("Upload Image")
                                .font(.title3.bold())
                        }
                        .foregroundStyle(Color.appBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.appLightestBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.appBlue, lineWidth: 1.5)
                        )
                    }
                    .disabled(scanViewModel.isScanning)
                    .padding(.horizontal, 20)

                    if scanViewModel.isScanning {
                        HStack(spacing: 8) {
                            ProgressView().tint(Color.appBlue)
                            Text(scanViewModel.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(Color.appGray)
                        }
                    }

                    if let error = scanViewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.appRed)
                            .padding(.horizontal, 20)
                            .multilineTextAlignment(.center)
                    }
                }

                Divider().padding(.vertical, 12)

                // Session history
                SessionHistoryView()
            }
            .navigationTitle("Lab Code Reader")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear").foregroundStyle(Color.appBlue)
                    }
                }
            }
            // Camera / photo picker
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(selectedImage: $selectedImage)
            }
            // Load image from photo library picker
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    photoPickerItem = nil
                    selectedImage = image
                }
            }
            // Start scan when an image arrives (camera or library)
            .onChange(of: selectedImage) { _, image in
                guard let image else { return }
                Task {
                    await scanViewModel.scan(image: image)
                    if let result = scanViewModel.scanResult {
                        if result.records.isEmpty {
                            scanViewModel.errorMessage = "No DataMatrix barcodes detected. Check image focus, lighting, and that the barcodes are DataMatrix format."
                            scanViewModel.scanResult = nil
                        } else {
                            navigateToResult = true
                        }
                    }
                }
            }
            // Navigate to result
            .navigationDestination(isPresented: $navigateToResult) {
                if let result = scanViewModel.scanResult {
                    ScanResultView(result: result)
                        .onDisappear {
                            selectedImage = nil
                            scanViewModel.scanResult = nil
                            navigateToResult = false
                        }
                }
            }
            // Settings sheet
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSettings = false }
                                    .foregroundStyle(Color.appBlue)
                            }
                        }
                }
            }
        }
    }
}
