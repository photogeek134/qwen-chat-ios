import Foundation
import UIKit

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let imageData: Data?
    let timestamp: Date

    /// True for the silent "Continue." turns that are injected between
    /// multi-pass responses. The UI can hide these from the chat transcript
    /// so the conversation looks seamless to the user.
    var isContinuationPrompt: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        imageData: Data? = nil,
        timestamp: Date = Date(),
        isContinuationPrompt: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageData = imageData
        self.timestamp = timestamp
        self.isContinuationPrompt = isContinuationPrompt
    }

    enum Role {
        case user
        case assistant
        case system
    }

    var isUser: Bool { role == .user }

    var image: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    /// Whether the model is currently in a thinking block (opened but not closed).
    var isThinking: Bool {
        content.contains("<think>") && !content.contains("</think>")
    }

    /// Parsed content split into thinking and visible portions.
    var parsedContent: (thinking: String?, visible: String) {
        let text = content

        guard let startRange = text.range(of: "<think>") else {
            return (nil, text)
        }

        if let endRange = text.range(of: "</think>") {
            // Complete thinking block
            let thinking = String(text[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = (
                String(text[text.startIndex..<startRange.lowerBound]) +
                String(text[endRange.upperBound...])
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking.isEmpty ? nil : thinking, visible)
        } else {
            // Still streaming thinking — no closing tag yet.
            // Return empty string (not nil) so the UI shows the thinking indicator.
            let thinking = String(text[startRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking, "")
        }
    }
}
