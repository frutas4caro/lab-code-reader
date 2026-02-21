// Views/CameraView.swift
import SwiftUI
import AVFoundation
import PhotosUI

/// Full-screen camera picker with live preview, shutter button, and photo library fallback.
struct CameraPickerView: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(capturedImage: $capturedImage)
                    .ignoresSafeArea()

                // Photo library button overlay
                HStack {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Library")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 40)
                    Spacer()
                }
            }
            .navigationTitle("Scan Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.appBlue)
                }
            }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            selectedImage = image
            dismiss()
        }
        .onChange(of: photoPickerItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                selectedImage = image
                dismiss()
            }
        }
    }
}

// MARK: - UIViewControllerRepresentable wrapper

struct CameraPreviewView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraPreviewView
        init(_ parent: CameraPreviewView) { self.parent = parent }
        func didCapture(image: UIImage) { parent.capturedImage = image }
    }
}

// MARK: - AVCapture delegate protocol

protocol CameraViewControllerDelegate: AnyObject {
    func didCapture(image: UIImage)
}

// MARK: - Camera view controller

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraViewControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var photoOutput = AVCapturePhotoOutput()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupShutterButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer })?.frame = view.bounds
    }

    private func setupCamera() {
#if targetEnvironment(simulator)
        let label = UILabel()
        label.text = "Camera not available\nin Simulator"
        label.textAlignment = .center
        label.numberOfLines = 2
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
#else
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else { return }

        session.addInput(input)
        session.addOutput(photoOutput)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)

        // Dimming overlay with square framing guide
        let side = min(view.bounds.width, view.bounds.height) * 0.8
        let squareRect = CGRect(
            x: (view.bounds.width - side) / 2,
            y: (view.bounds.height - side) / 2,
            width: side, height: side
        )
        let maskPath = UIBezierPath(rect: view.bounds)
        maskPath.append(UIBezierPath(rect: squareRect).reversing())
        let overlay = CAShapeLayer()
        overlay.path = maskPath.cgPath
        overlay.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        view.layer.addSublayer(overlay)

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
#endif
    }

    private func setupShutterButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "camera.circle.fill"), for: .normal)
        button.tintColor = .white
        button.contentVerticalAlignment = .fill
        button.contentHorizontalAlignment = .fill
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.delegate?.didCapture(image: image) }
    }
}
