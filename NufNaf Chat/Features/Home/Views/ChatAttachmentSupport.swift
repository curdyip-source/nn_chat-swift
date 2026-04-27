import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PickedChatAttachment {
    let id = UUID()
    let data: Data
    let filename: String
    let mimeType: String
    let attachmentKind: String
}

extension PickedChatAttachment: Identifiable {}

extension PickedChatAttachment {
    var isPhoto: Bool {
        attachmentKind == "photo"
    }
}

struct LocalAttachmentPreview: Identifiable {
    let id = UUID()
    let url: URL
}

struct PhotoLibraryAttachmentPicker: UIViewControllerRepresentable {
    let onPick: (PickedChatAttachment) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: (PickedChatAttachment) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (PickedChatAttachment) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }

            let provider = result.itemProvider
            let typeIdentifier = provider.registeredTypeIdentifiers.first
                ?? UTType.image.identifier
            let type = UTType(typeIdentifier) ?? .image

            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                DispatchQueue.main.async {
                    guard let data else {
                        self.onCancel()
                        return
                    }
                    let filename = [provider.suggestedName, type.preferredFilenameExtension].compactMap { $0 }.joined(separator: provider.suggestedName == nil ? "" : ".")
                    self.onPick(
                        PickedChatAttachment(
                            data: data,
                            filename: filename.isEmpty ? "photo.jpg" : filename,
                            mimeType: type.preferredMIMEType ?? "image/jpeg",
                            attachmentKind: "photo"
                        )
                    )
                }
            }
        }
    }
}

struct CameraAttachmentPicker: UIViewControllerRepresentable {
    let onPick: (PickedChatAttachment) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.delegate = context.coordinator
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.modalPresentationStyle = .fullScreen
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPick: (PickedChatAttachment) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (PickedChatAttachment) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }

            onPick(
                PickedChatAttachment(
                    data: data,
                    filename: "camera-\(Int(Date().timeIntervalSince1970)).jpg",
                    mimeType: "image/jpeg",
                    attachmentKind: "photo"
                )
            )
        }
    }
}

struct FileAttachmentPicker: UIViewControllerRepresentable {
    let onPick: (PickedChatAttachment) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let contentTypes: [UTType] = [.pdf, .plainText, .rtf, .spreadsheet, .data, .item]
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (PickedChatAttachment) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (PickedChatAttachment) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }

            let secured = url.startAccessingSecurityScopedResource()
            defer {
                if secured {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension) ?? .data
                onPick(
                    PickedChatAttachment(
                        data: data,
                        filename: url.lastPathComponent,
                        mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                        attachmentKind: "file"
                    )
                )
            } catch {
                onCancel()
            }
        }
    }
}

struct LocalFileQuickLookPreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

struct PhotoAttachmentViewer: View {
    let attachment: HomeMessageAttachment
    let onDismiss: () -> Void

    @State private var contentScale: CGFloat = 1
    @State private var accumulatedScale: CGFloat = 1
    @State private var contentOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let dismissProgress = min(max(abs(dragOffset.height) / 240, 0), 1)

            ZStack(alignment: .topTrailing) {
                Color.black.opacity(1 - dismissProgress * 0.55)
                    .ignoresSafeArea()

                if let url = attachment.mediaURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            VStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 42, weight: .semibold))
                                Text("Не удалось загрузить фото")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                        default:
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .scaleEffect(contentScale)
                    .offset(x: contentOffset.width + dragOffset.width, y: contentOffset.height + dragOffset.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .gesture(magnificationGesture)
                    .simultaneousGesture(dragGesture)
                    .simultaneousGesture(doubleTapGesture)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
        .statusBarHidden(true)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                contentScale = min(max(accumulatedScale * value, 1), 4)
            }
            .onEnded { _ in
                accumulatedScale = contentScale
                if contentScale <= 1.01 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        contentScale = 1
                        accumulatedScale = 1
                        contentOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if contentScale > 1.01 {
                    contentOffset = CGSize(
                        width: contentOffset.width + value.translation.width * 0.02,
                        height: contentOffset.height + value.translation.height * 0.02
                    )
                } else {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                if contentScale <= 1.01, value.translation.height > 140 {
                    onDismiss()
                    return
                }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    dragOffset = .zero
                    if contentScale <= 1.01 {
                        contentOffset = .zero
                    }
                }
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    if contentScale > 1.01 {
                        contentScale = 1
                        accumulatedScale = 1
                        contentOffset = .zero
                    } else {
                        contentScale = 2
                        accumulatedScale = 2
                    }
                }
            }
    }
}

struct ChatAttachmentDraftSheet: View {
    let attachment: PickedChatAttachment
    let isSending: Bool
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                previewCard

                VStack(alignment: .leading, spacing: 6) {
                    Text(attachment.filename)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(attachmentMeta)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Отмена")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)

                    Button(action: onSend) {
                        Group {
                            if isSending {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Отправить")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
                .padding(.bottom, 50)
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .disabled(isSending)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var previewCard: some View {
        if attachment.isPhoto, let image = UIImage(data: attachment.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            VStack(spacing: 14) {
                Image(systemName: fileIconName)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))

                Text("Проверьте файл перед отправкой")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var attachmentMeta: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeTitle = formatter.string(fromByteCount: Int64(attachment.data.count))
        return attachment.isPhoto ? "Фото • \(sizeTitle)" : "Файл • \(sizeTitle)"
    }

    private var fileIconName: String {
        let mimeType = attachment.mimeType.lowercased()
        if mimeType.contains("pdf") {
            return "doc.richtext"
        }
        if mimeType.contains("sheet") || mimeType.contains("excel") {
            return "tablecells"
        }
        if mimeType.contains("word") {
            return "doc.text"
        }
        return "doc"
    }
}