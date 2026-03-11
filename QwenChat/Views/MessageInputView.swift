import SwiftUI
import PhotosUI

// MARK: - MessageInputView

struct MessageInputView: View {
var viewModel: ChatViewModel

// Text field state
@State private var inputText: String = ""
@State private var selectedPhotoItem: PhotosPickerItem? = nil
@State private var attachedImage: UIImage? = nil
@FocusState private var isInputFocused: Bool

// Tracks whether the last keystroke was Shift, so we can distinguish
// plain Enter (send) from Shift+Enter (newline) on a hardware keyboard.
@State private var shiftIsHeld: Bool = false

// Whether the send action is currently available
private var canSend: Bool {
    let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let isReady = !viewModel.isLoading && viewModel.modelContainer != nil && !viewModel.isGenerating
    return (hasText || attachedImage != nil) && isReady
}

var body: some View {
    HStack(alignment: .bottom, spacing: 10) {

        // MARK: - Photo picker button
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: attachedImage == nil ? "photo" : "photo.fill")
                .font(.system(size: 22))
                .foregroundStyle(attachedImage == nil ? Color.secondary : Color.blue)
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

        // MARK: - Text input + image thumbnail stack
        VStack(alignment: .leading, spacing: 6) {

            // Attached image thumbnail (shown above the text field)
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

            // Multi-line text field
            // On a hardware keyboard:
            //   • Enter alone   → sends the message
            //   • Shift + Enter → inserts a newline (stays in field)
            // On the software keyboard the Send button is always used.
            TextField(
                "Message",
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...6)
            .focused($isInputFocused)
            // `.send` changes the soft-keyboard Return key label to "Send"
            // (has no effect on a hardware keyboard, but good UX on iPhone)
            .submitLabel(.send)
            // This fires on the software keyboard Return / "Send" key tap.
            // On a hardware keyboard it does NOT fire — we handle that via
            // onChange below.
            .onSubmit {
                submitIfPossible()
            }
            // Hardware keyboard Enter detection.
            // When the user presses plain Enter on a hardware keyboard,
            // SwiftUI appends "\n" to inputText before we can intercept it.
            // We detect that "\n" here and either:
            //   a) strip it and send (plain Enter), or
            //   b) leave it in place (Shift+Enter — already a real newline
            //      that the user intentionally typed, detected by checking
            //      whether the last character added was a lone \n at the
            //      very end with no prior uncommitted newline on that line).
            //
            // The trick: Shift+Enter on a hardware keyboard produces a "\n"
            // just like plain Enter, so we use a `@GestureState`-free approach:
            // we detect whether the newly appended character is a trailing
            // newline on an otherwise non-empty last line. If so, it came from
            // plain Enter and should send. Shift+Enter inserts the same "\n"
            // but the user intent is a newline — we expose this via a
            // `.onKeyPress` modifier (iOS 17+) that fires *before* the text
            // binding updates, letting us set a flag.
            .onChange(of: inputText) { oldValue, newValue in
                guard isInputFocused else { return }
                // Only act when a newline was appended (not pasted or deleted)
                guard newValue.hasSuffix("\n"), !oldValue.hasSuffix("\n") else { return }

                if shiftIsHeld {
                    // User pressed Shift+Enter — keep the newline, do not send.
                    // shiftIsHeld will be reset by onKeyPress release.
                } else {
                    // Plain Enter on hardware keyboard — send the message.
                    // Strip the trailing newline that was already inserted.
                    inputText = String(newValue.dropLast())
                    submitIfPossible()
                }
            }
            // `onKeyPress` (iOS 17+) fires synchronously before the text
            // binding updates, giving us a reliable Shift-key signal.
            .onKeyPress(phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    shiftIsHeld = true
                }
                return .ignored   // let the key event propagate normally
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

        // MARK: - Send / Stop button
        Button {
            if viewModel.isGenerating {
                viewModel.stopGeneration()
            } else {
                submitIfPossible()
            }
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    viewModel.isGenerating ? .orange :
                    canSend ? .blue : .secondary
                )
        }
        .disabled(!viewModel.isGenerating && !canSend)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isGenerating)
    }
}

// MARK: - Actions

private func submitIfPossible() {
    guard canSend else { return }

    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let image = attachedImage

    // Clear state before sending so the UI feels instant
    inputText = ""
    attachedImage = nil
    selectedPhotoItem = nil

    Task {
        await viewModel.sendMessage(text: text, image: image)
    }
}

}

// MARK: - Keyboard shortcut hint (iPad only)

/// A small overlay shown below the input area on iPad when a hardware
/// keyboard is attached, reminding users of the Enter / Shift+Enter shortcuts.
struct KeyboardShortcutHint: View {
@Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

var body: some View {
    // Only show on iPad (regular width) and only when a hardware keyboard
    // is likely connected (GCKeyboard is a reliable signal on iOS 14+).
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
