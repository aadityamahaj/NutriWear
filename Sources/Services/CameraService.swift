import AVFoundation
import UIKit
import SwiftUI

/// Non-isolated engine that owns the AVCaptureSession and all capture work.
/// It runs entirely off the main actor on its own serial queue, so it never
/// touches main-actor state. UI state is published separately by CameraService.
final class CameraEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "nutriwear.camera.engine")
    private var configured = false
    private var captureHandler: ((UIImage?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else {
                completion(nil); return
            }
            self.captureHandler = completion
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        configured = true
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        let handler = captureHandler
        captureHandler = nil
        handler?(image)
    }
}

/// Main-actor façade exposing camera state to SwiftUI and bridging to the engine.
@MainActor
final class CameraService: ObservableObject {

    enum AuthState { case unknown, authorized, denied }

    @Published var authState: AuthState = .unknown
    @Published var isRunning = false

    private let engine = CameraEngine()

    /// The capture session for the SwiftUI preview layer.
    var session: AVCaptureSession { engine.session }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // MARK: - Permissions

    func requestAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            authState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authState = granted ? .authorized : .denied
        default:
            authState = .denied
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !Self.isSimulator, authState == .authorized else { return }
        engine.start()
        isRunning = true
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    // MARK: - Capture

    func capturePhoto() async -> UIImage? {
        guard !Self.isSimulator, isRunning else { return nil }
        return await withCheckedContinuation { continuation in
            engine.capture { image in
                continuation.resume(returning: image)
            }
        }
    }
}

/// SwiftUI wrapper around the AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
