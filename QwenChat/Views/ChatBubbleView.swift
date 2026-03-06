import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage

    @State private var showThinking = false

    var body: some View {
        let parsed = message.parsedContent
        let isThinking = message.isThinking

        HStack(alignment: .top) {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Thinking block — shown while streaming or after completion
                if isThinking || parsed.thinking != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isThinking {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                }
                                Text(isThinking ? "Thinking..." : "Thought process")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showThinking || isThinking, let thinking = parsed.thinking, !thinking.isEmpty {
                            Text(thinking)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Visible response
                if !parsed.visible.isEmpty {
                    Text(LocalizedStringKey(parsed.visible))
                        .textSelection(.enabled)
                        .padding(12)
                        .background(message.isUser ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(message.isUser ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            if !message.isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
