import Foundation
import UIKit

// MARK: - Role

enum MessageRole {
    case system, user, assistant
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable {
    let id: UUID
    var role: MessageRole
    var content: String
    var imageData: Data?

    // MARK: File attachment fields
    // The display name shown in the bubble (e.g. "Report.pdf")
    var attachedFileName: String?
    // The extracted plain text sent to the model as part of the prompt.
    // For PDFs this is the text layer; for plain text files it's the raw content.
    // This is NOT stored as the message content directly — it gets prepended
    // to the user's typed prompt in ChatViewModel.sendMessage().
    var attachedFileText: String?

    // MARK: Continuation flag
    // True for the silent "Continue." turns injected between multi-pass responses.
    // The UI filters these out of the visible transcript.
    var isContinuationPrompt: Bool

    // Convenience: materialise UIImage from stored JPEG data
    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        imageData: Data? = nil,
        attachedFileName: String? = nil,
        attachedFileText: String? = nil,
        isContinuationPrompt: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageData = imageData
        self.attachedFileName = attachedFileName
        self.attachedFileText = attachedFileText
        self.isContinuationPrompt = isContinuationPrompt
    }
}
