import SwiftUI
import PhotosUI

/// Minimal PHPicker wrapper. Used as the camera fallback on the Simulator and
/// anywhere the user wants to analyze an existing photo.
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: @MainActor (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: @MainActor (UIImage) -> Void
        init(onPick: @escaping @MainActor (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            let handler = onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                // Hop to the main actor before invoking the SwiftUI callback.
                Task { @MainActor in handler(image) }
            }
        }
    }
}
