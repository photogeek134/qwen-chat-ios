import SwiftUI
import PhotosUI

// MARK: - MessageInputView

struct MessageInputView: View {
    var viewModel: ChatViewModel

    @State private var inputText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var attachedImage: UIImage? = nil
    @State private var attachedFileName: String? = nil
    @State private var attachedFileText: String? = nil
    @FocusState private var isInputFocused: Bool
    @State private var shiftIsHeld: Bool = false

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isReady = !viewModel.isLoading && viewModel.modelContainer != nil && !viewModel.isGenerating
        return (hasText || attachedImage != nil || attachedFileText != nil) && isReady
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {

            // MARK: - Photo picker
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: attachedImage == nil ? "photo" : "photo.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(attachedImage == nil ? .secondary : .blue)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { @MainActor in
                    if let newItem,
                       let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        attachedImage = image
                    } else {
                        attachedImage = nil
                    }
                }
            }
            .disabled(viewModel.isLoading || viewModel.modelContainer == nil)

            // MARK: - File picker
            FilePickerButton { fileName, fileText in
                attachedFileName = fileName
                attachedFileText = fileText
            }
            .disabled(viewModel.isLoading || viewModel.modelContainer == nil)

            // MARK: - Text + attachment stack
            VStack(alignment: .leading, spacing: 6) {

                // Image thumbnail
                if let image = attachedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    attachedImage = nil
                                    selectedPhotoItem = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .offset(x: 6, y: -6)
                                }
                            }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                // File attachment chip
                if let fileName = attachedFileName {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(fileName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            attachedFileName = nil
                            attachedFileText = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 4)
                }

                // Text field
                TextField("Message", text: $inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitIfPossible()
                    }
                    .onChange(of: inputText) { oldValue, newValue in
                        guard isInputFocused else { return }
                        guard newValue.hasSuffix("\n"), !oldValue.hasSuffix("\n") else { return }
                        if shiftIsHeld {
                            // Shift+Enter: keep newline, don't send
                        } else {
                            inputText = String(newValue.dropLast())
                            submitIfPossible()
                        }
                    }
                    .onKeyPress(phases: .down) { press in
                        if press.modifiers.contains(.shift) { shiftIsHeld = true }
                        return .ignored
                    }
                    .onKeyPress(phases: .up) { _ in
                        shiftIsHeld = false
                        return .ignored
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color(.systemGray4), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    )
            }

            // MARK: - Keyboard dismiss + Send/Stop buttons
            VStack(spacing: 8) {
                // Keyboard dismiss — only useful when software keyboard is up
                if isInputFocused {
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale))
                }

                // Send / Stop
                Button {
                    if viewModel.isGenerating {
                        viewModel.stopGeneration()
                    } else {
                        submitIfPossible()
                    }
                } label: {
                    Image(systemName: viewModel.isGenerating
                          ? "stop.circle.fill"
                          : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.isGenerating ? .orange :
                            canSend ? .blue : .secondary
                        )
                }
                .disabled(!viewModel.isGenerating && !canSend)
            }
            .animation(.easeInOut(duration: 0.15), value: isInputFocused)
        }
    }

    // MARK: - Submit

    private func submitIfPossible() {
        guard canSend else { return }

        var finalText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prepend file content as context before the user's typed prompt
        if let fileText = attachedFileText, let fileName = attachedFileName {
            finalText = """
            [Attached file: \(fileName)]

            \(fileText)

            ---

            \(finalText)
            """
        }

        let image = attachedImage
        let fileName = attachedFileName

        // Clear state immediately so UI feels instant
        inputText = ""
        attachedImage = nil
        selectedPhotoItem = nil
        attachedFileName = nil
        attachedFileText = nil
        isInputFocused = false

        Task {
            await viewModel.sendMessage(
                text: finalText,
                image: image,
                attachedFileName: fileName
            )
        }
    }
}

// MARK: - Keyboard shortcut hint (iPad only)

struct KeyboardShortcutHint: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Enter to send  •  Shift+Enter for new line")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, 2)
        }
    }
}
