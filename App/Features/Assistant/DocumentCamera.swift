import SwiftUI
import VisionKit

/// Съёмка чека: системная камера документов сама находит края и выравнивает перспективу,
/// умеет снять несколько страниц — длинный чек можно снять частями. Распознавания текста здесь нет:
/// страницы уходят модели картинками (`ReceiptImagePreparer` режет и сжимает их в ядре).
struct DocumentCamera: UIViewControllerRepresentable {
    /// Камеры документов нет на симуляторе и старых устройствах — кнопку «Снять чек» тогда не показываем.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    let onScan: ([Data]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([Data]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
            onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
