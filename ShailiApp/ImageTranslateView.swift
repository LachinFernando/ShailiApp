import SwiftUI
import PhotosUI
import UIKit
import Alamofire
import SwiftyJSON


struct ImageTranslateView: View {
    @StateObject private var vm = ImageTranslationViewModel()

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    @State private var showOriginalSheet = false
    @State private var showTranslationSheet = false

    var body: some View {
        VStack(spacing: 0) {

            // Top bar
            HStack {
                Text("Logo")
                    .font(.system(size: 22))
                Spacer()
                Text("TranslateRX")
                    .font(.system(size: 22))
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(Color.black).frame(height: 3)

            // Actions row
            HStack(alignment: .top) {

                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                        Text("File Upload\nIcon")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    vm.toggleLanguage()
                } label: {
                    VStack(spacing: 6) {
                        Text("Language")
                            .font(.system(size: 18))
                        Text(vm.toggledLanguage.capitalized)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    showCamera = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Camera")
                            .font(.system(size: 14))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Rectangle().fill(Color.black).frame(height: 3)

            // Main content
            VStack(spacing: 16) {

                // Image square
                GeometryReader { geo in
                    let side = min(geo.size.width, 300)
                    ZStack {
                        Rectangle()
                            .stroke(Color.black.opacity(0.75), lineWidth: 2)
                            .frame(width: side, height: side)

                        if let img = vm.uiImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: side - 8, height: side - 8)
                                .clipped()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 320)
                .padding(.top, 10)

                // Translate button
                Button {
                    vm.getImageTranslationContents(toggledLanguage: vm.toggledLanguage)
                } label: {
                    Text("Translate Image")
                        .font(.system(size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: 280)
                        .frame(height: 52)
                }
                .background(Capsule().stroke(Color.black.opacity(0.75), lineWidth: 2))
                .disabled(vm.uiImage == nil || vm.isProcessing)

                // Loader OR results
                if vm.isProcessing {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 6)
                } else {
                    if !vm.isHidden {
                        ContentPillButton(
                            title: "Original",
                            text: vm.originalText.isEmpty ? "Image Content" : "Image Content in English",
                            isPlaceholder: vm.originalText.isEmpty
                        ) {
                            if !vm.originalText.isEmpty { showOriginalSheet = true }
                        }

                        ContentPillButton(
                            title: "Translation",
                            text: vm.translationText.isEmpty ? "Image Content" : "Image Translation in \(vm.toggledLanguage)",
                            isPlaceholder: vm.translationText.isEmpty
                        ) {
                            if !vm.translationText.isEmpty { showTranslationSheet = true }
                        }
                    }
                }

                if !vm.errorMessage.isEmpty {
                    Text(vm.errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task { await vm.loadFromPhotosPickerItem(newItem) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                vm.setImage(image)
            }
        }
        .sheet(isPresented: $showOriginalSheet) {
            TextSheet(title: "Original", text: vm.originalText)
        }
        .sheet(isPresented: $showTranslationSheet) {
            TextSheet(title: "Translation", text: vm.translationText)
        }
    }
}

private struct ContentPillButton: View {
    let title: String
    let text: String
    let isPlaceholder: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: 320)
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .background(Capsule().stroke(Color.black.opacity(0.75), lineWidth: 2))
    }
}

private struct TextSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}


final class ImageTranslationViewModel: ObservableObject {

    @Published var uiImage: UIImage?
    @Published var toggled: Bool = true
    @Published var toggledLanguage: String = "mandarin" // toggles between "mandarin" and "spanish"
    @Published var isProcessing: Bool = false
    @Published var isHidden: Bool = true

    @Published var extractedImageId: String = ""
    @Published var originalText: String = ""
    @Published var translationText: String = ""
    @Published var errorMessage: String = ""

    private let invokeEndpoint = "https://yx1lmhfs27.execute-api.us-east-1.amazonaws.com/research-program/image-translate-invoke"
    private let pollingEndpoint = "https://yx1lmhfs27.execute-api.us-east-1.amazonaws.com/research-program/fetch_image_translation"

    private let maxPollAttempts = 45
    private let pollDelaySeconds: Double = 2.0

    func toggleLanguage() {
        toggled = !toggled
        toggledLanguage = toggled ? "mandarin" : "spanish"
    }

    func setImage(_ image: UIImage?) {
        uiImage = image
        // reset previous results
        extractedImageId = ""
        originalText = ""
        translationText = ""
        errorMessage = ""
        isProcessing = false
    }

    @MainActor
    func loadFromPhotosPickerItem(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                setImage(img)
            } else {
                errorMessage = "Could not load the selected image."
            }
        } catch {
            errorMessage = "Failed to load image from Photos."
        }
    }

    // - base64
    // - createPayload with httpMethod + body
    // - AF.request(...).responseJSON { ... }
    // - on success start polling
    func getImageTranslationContents(toggledLanguage: String) {
        isProcessing = true
        errorMessage = ""
        originalText = ""
        translationText = ""
        extractedImageId = ""

        guard let image = uiImage else {
            errorMessage = "Please select or capture an image first."
            isProcessing = false
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.50) else { // can change the image quality
            errorMessage = "Could not convert image to JPEG."
            isProcessing = false
            return
        }

        let base64String = imageData.base64EncodedString()

        let createPayload: [String: Any] = [
            "httpMethod": "POST",
            "body": [
                "imageBytes": base64String,
                "language": toggledLanguage
            ]
        ]

        AF.request(
            invokeEndpoint,
            method: .post,
            parameters: createPayload,
            encoding: JSONEncoding.default
        )
        .responseJSON { response in
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                print(json)
                let statusCode = json["statusCode"].intValue
                if statusCode != 200 {
                    let msg = json["error"].arrayValue.first?.stringValue ?? "Invoke API returned an error."
                    self.errorMessage = msg
                    self.isProcessing = false
                    return
                }

                let imageId = json["data"]["imageId"].stringValue
                self.extractedImageId = imageId

                guard !imageId.isEmpty else {
                    self.errorMessage = "Failed to get imageId."
                    self.isProcessing = false
                    self.isHidden = false
                    return
                }

                // Start polling
                self.pollImageTranslationStatus(imageId: imageId, attempt: 0)

            case .failure(let error):
                self.errorMessage = "Error: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }

    func pollImageTranslationStatus(imageId: String, attempt: Int) {
        if attempt >= maxPollAttempts {
            self.errorMessage = "Timed out while waiting for translation to complete."
            self.isProcessing = false
            self.isHidden = false
            return
        }

        let pollPayload: [String: Any] = [
            "httpMethod": "POST",
            "body": [
                "imageId": imageId
            ]
        ]

        AF.request(
            pollingEndpoint,
            method: .post,
            parameters: pollPayload,
            encoding: JSONEncoding.default
        )
        .responseJSON { response in
            switch response.result {
            case .success(let value):
                let json = JSON(value)

                let statusCode = json["statusCode"].intValue
                if statusCode != 200 {
                    let msg = json["error"].arrayValue.first?.stringValue ?? "Polling API returned an error."
                    self.errorMessage = msg
                    self.isProcessing = false
                    self.isHidden = false
                    return
                }

                let status = json["data"]["status"].stringValue.uppercased()

                if status == "COMPLETED" {
                    // NOTE: backend key is "orginalText" (typo) per your response sample
                    self.originalText = json["data"]["orginalText"].stringValue
                    self.translationText = json["data"]["translation"].stringValue
                    self.isProcessing = false
                    self.isHidden = false
                } else {
                    // poll again after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.pollDelaySeconds) {
                        self.pollImageTranslationStatus(imageId: imageId, attempt: attempt + 1)
                    }
                }

            case .failure(let error):
                self.errorMessage = "Error: \(error.localizedDescription)"
                self.isProcessing = false
                self.isHidden = false
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ImageTranslateView()
}
