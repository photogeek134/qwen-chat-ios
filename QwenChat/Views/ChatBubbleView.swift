import SwiftUI

// MARK: - ChatBubbleView

struct ChatBubbleView: View {
    let message: ChatMessage

    @State private var showCopied = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 44) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {

                // MARK: Attached image (user messages only)
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // MARK: Attached file name (user messages only)
                if let fileName = message.attachedFileName {
                    Label(fileName, systemImage: "doc.text")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.secondary)
                }

                // MARK: Message text bubble
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)   // native iOS text selection
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isUser
                                ? Color.blue
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .foregroundStyle(isUser ? .white : .primary)
                        // Long-press context menu with Copy action
                        .contextMenu {
                            Button {
                                copyToClipboard(message.content)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            // Share sheet
                            ShareLink(item: message.content) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                }

                // MARK: Copy confirmation + copy button row (assistant only)
                if !isUser {
                    HStack(spacing: 12) {
                        // Inline copy button — always visible for assistant messages
                        Button {
                            copyToClipboard(message.content)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                                Text(showCopied ? "Copied" : "Copy")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .animation(.easeInOut(duration: 0.15), value: showCopied)
                    }
                    .padding(.leading, 4)
                }
            }

            if !isUser { Spacer(minLength: 44) }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        // Strip the trailing performance stats line before copying
        // e.g. "\n\n_(4.2 tok/s)_" is useful in-app but noisy on clipboard
        let cleaned = text
            .replacingOccurrences(
                of: #"\n\n_\(.*\)_$"#,
                with: "",
                options: .regularExpression
            )
        UIPasteboard.general.string = cleaned

        // Brief "Copied" confirmation that auto-resets
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopied = false
        }
    }
}
