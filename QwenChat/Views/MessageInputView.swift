import PhotosUI
import SwiftUI

struct MessageInputView: View {
    @Binding var messageText: String
    @Binding var selectedImage: UIImage?
    let showCamera: Bool
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var photosPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            if let image = selectedImage {
                ImagePreviewView(image: image) {
                    selectedImage = nil
                }
            }

            HStack(spacing: 8) {
                if showCamera {
                    PhotosPicker(selection: $photosPickerItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                    }
                    .onChange(of: photosPickerItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImage = image
                            }
                        }
                    }
                }

                TextField("Message...", text: $messageText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                if isGenerating {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImage == nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
