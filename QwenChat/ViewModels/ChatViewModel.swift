import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
var messages: [ChatMessage] = []
var selectedModel: AppModel = .qwen3_5_0_8B
var isLoading = false
var isGenerating = false
var loadProgress: Double = 0
var loadingStatus: String = “”
var errorMessage: String?

```
// Set to true when the last generation was cut off by maxTokens
// (not by EOS). The UI can observe this to show a "Continue" button.
var isTruncated = false

private(set) var modelContainer: ModelContainer?
private var generationTask: Task<Void, Never>?

private static let gpuCacheLimit = 512 * 1024 * 1024 // 512 MB

// MARK: - RAM-tiered token budget

/// Maximum tokens per generation pass, scaled to the device's RAM.
///
/// Why per-pass rather than a total cap?
/// Re-encoding the full conversation history on each continuation round
/// is expensive, so we keep individual passes short enough to stay within
/// the GPU memory budget and let the user explicitly request more via a
/// "Continue" button rather than auto-looping.
///
/// Tiers:
///   < 6 GB  → 1024  (older/lower-end iPhones)
///   6–7 GB  → 2048  (iPhone 14 / base iPad)
///   8–11 GB → 4096  (iPhone 15 Pro / mid iPads)
///   ≥ 12 GB → 8192  (iPad Pro M4/M5)
static var maxTokensPerPass: Int {
    let gb = DeviceMemory.bucketGB
    switch gb {
    case ..<6:   return 1_024
    case 6..<8:  return 2_048
    case 8..<12: return 4_096
    default:     return 8_192
    }
}

// MARK: - Model Loading

func loadModel() async {
    guard !isLoading else { return }

    isLoading = true
    loadProgress = 0
    loadingStatus = "Downloading \(selectedModel.displayName)..."
    errorMessage = nil

    do {
        MLX.GPU.set(cacheLimit: Self.gpuCacheLimit)

        let container = try await loadModelContainer(
            id: selectedModel.huggingFaceID
        ) { progress in
            Task { @MainActor in
                self.loadProgress = progress.fractionCompleted
                self.loadingStatus = "Downloading \(self.selectedModel.displayName)... \(Int(progress.fractionCompleted * 100))%"
            }
        }

        modelContainer = container
        loadingStatus = "\(selectedModel.displayName) ready"
    } catch {
        errorMessage = "Failed to load model: \(error.localizedDescription)"
        loadingStatus = "Load failed"
    }

    isLoading = false
}

func switchModel(to newModel: AppModel) async {
    guard newModel != selectedModel else { return }

    stopGeneration()

    modelContainer = nil
    MLX.GPU.set(cacheLimit: 0)
    MLX.GPU.clearCache()

    selectedModel = newModel
    messages.removeAll()

    await loadModel()
}

// MARK: - Background Handling

func handleBackgrounding() {
    stopGeneration()
}

func releaseModel() {
    stopGeneration()
    modelContainer = nil
    MLX.GPU.set(cacheLimit: 0)
    MLX.GPU.clearCache()
    loadingStatus = "Model released"
}

// MARK: - Message Sending

func sendMessage(text: String, image: UIImage? = nil) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || image != nil else { return }
    guard !isGenerating else { return }

    isTruncated = false

    let imageData = image?.jpegData(compressionQuality: 0.5)
    print("[DEBUG] sendMessage: text='\(trimmed)', hasImage=\(image != nil)")
    let userMessage = ChatMessage(role: .user, content: trimmed, imageData: imageData)
    messages.append(userMessage)

    generationTask = Task {
        await generate()
    }
}

/// Called from the UI's "Continue" button when the previous response was
/// cut off at maxTokens. Appends a silent continuation prompt and runs
/// another generation pass.
func continueGeneration() {
    guard isTruncated, !isGenerating else { return }

    isTruncated = false

    // Append a minimal continuation instruction as a user turn.
    // Keeping it short avoids polluting the visible conversation history;
    // the ChatBubbleView can choose to hide messages flagged as continuations.
    let continueMessage = ChatMessage(
        role: .user,
        content: "Continue.",
        imageData: nil,
        isContinuationPrompt: true  // flag so the UI can hide it if desired
    )
    messages.append(continueMessage)

    generationTask = Task {
        await generate()
    }
}

func stopGeneration() {
    generationTask?.cancel()
    generationTask = nil
    isGenerating = false
}

// MARK: - Generation

private func generate() async {
    guard let container = modelContainer else {
        errorMessage = "Model not loaded"
        return
    }

    isGenerating = true

    var chatMessages: [Chat.Message] = [
        .system("You are a helpful assistant.")
    ]

    for msg in messages {
        switch msg.role {
        case .user:
            if let img = msg.image, let ciImage = CIImage(image: img) {
                print("[DEBUG] generate: user message with image, extent=\(ciImage.extent)")
                chatMessages.append(.user(msg.content, images: [.ciImage(ciImage)]))
            } else {
                chatMessages.append(.user(msg.content))
            }
        case .assistant:
            chatMessages.append(.assistant(msg.content))
        case .system:
            break
        }
    }

    let assistantMessage = ChatMessage(role: .assistant, content: "", imageData: nil)
    messages.append(assistantMessage)
    let assistantIndex = messages.count - 1

    var lastInfo: GenerateInfo?
    var hitTokenLimit = false

    do {
        let input = UserInput(
            chat: chatMessages,
            processing: .init(resize: CGSize(width: 512, height: 512)),
            additionalContext: ["enable_thinking": false]
        )
        print("[DEBUG] generate: \(input.images.count) image(s), maxTokensPerPass=\(Self.maxTokensPerPass)")

        let params = GenerateParameters(
            maxTokens: Self.maxTokensPerPass,
            temperature: 0.7
        )
        let lmInput = try await container.prepare(input: input)
        let stream = try await container.generate(input: lmInput, parameters: params)

        for await generation in stream {
            if Task.isCancelled { break }

            switch generation {
            case .chunk(let text):
                messages[assistantIndex].content += text

            case .info(let info):
                lastInfo = info
                // Detect whether generation stopped due to the token cap
                // rather than the model naturally finishing (EOS token).
                // GenerateInfo.stopReason is a String in mlx-swift-lm;
                // the value is "max_tokens" when the budget is exhausted.
                hitTokenLimit = (info.stopReason == "max_tokens")

            default:
                break
            }
        }

        // Append performance stats once generation is done
        if let info = lastInfo {
            let stats = String(format: "%.1f tok/s · %d tokens", info.tokensPerSecond, info.promptTokens + info.generationTokens)
            messages[assistantIndex].content += "\n\n_(\(stats))_"
        }

        // Signal to the UI that more content may be available
        isTruncated = hitTokenLimit && !Task.isCancelled

    } catch {
        if !Task.isCancelled {
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
        }
    }

    isGenerating = false
}
```

}