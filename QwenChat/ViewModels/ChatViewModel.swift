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
    var loadingStatus: String = ""
    var errorMessage: String?

    private(set) var modelContainer: ModelContainer?
    private var generationTask: Task<Void, Never>?

    private static let maxTokens = 1024
    private static let gpuCacheLimit = 512 * 1024 * 1024 // 512 MB

    // MARK: - Model Loading

    func loadModel() async {
        guard !isLoading else { return }

        isLoading = true
        loadProgress = 0
        loadingStatus = "Downloading \(selectedModel.displayName)..."
        errorMessage = nil

        do {
            // Set GPU cache limit before loading
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

        // Release current model and flush GPU cache
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

        // Compress image to reduce memory footprint in chat history
        let imageData = image?.jpegData(compressionQuality: 0.5)
        print("[DEBUG] sendMessage: text='\(trimmed)', hasImage=\(image != nil), imageSize=\(image?.size ?? .zero), jpegBytes=\(imageData?.count ?? 0)")
        let userMessage = ChatMessage(role: .user, content: trimmed, imageData: imageData)
        messages.append(userMessage)

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

        // Build chat messages with images attached to the Chat.Message objects.
        // The UserInput(chat:) initializer extracts images from messages automatically.
        var chatMessages: [Chat.Message] = [
            .system("You are a helpful assistant.")
        ]

        for msg in messages {
            switch msg.role {
            case .user:
                if let img = msg.image, let ciImage = CIImage(image: img) {
                    print("[DEBUG] generate: user message with image, CIImage extent=\(ciImage.extent)")
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

        // Add empty assistant message for streaming
        let assistantMessage = ChatMessage(role: .assistant, content: "", imageData: nil)
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        var lastInfoSummary: String?

        do {
            // Use init(chat:) which extracts images from Chat.Message objects
            let input = UserInput(
                chat: chatMessages,
                processing: .init(resize: CGSize(width: 512, height: 512)),
                additionalContext: ["enable_thinking": false]
            )
            print("[DEBUG] generate: UserInput created with \(input.images.count) images")

            let params = GenerateParameters(maxTokens: Self.maxTokens, temperature: 0.7)
            let lmInput = try await container.prepare(input: input)
            print("[DEBUG] generate: LMInput prepared, hasImage=\(lmInput.image != nil), hasVideo=\(lmInput.video != nil), tokenCount=\(lmInput.text.tokens.shape)")
            let stream = try await container.generate(input: lmInput, parameters: params)

            for await generation in stream {
                if Task.isCancelled { break }

                switch generation {
                case .chunk(let text):
                    messages[assistantIndex].content += text
                case .info(let info):
                    // Store only the last info summary (replace any previous one)
                    lastInfoSummary = String(format: "%.1f tok/s", info.tokensPerSecond)
                default:
                    break
                }
            }

            // Append performance stats once after generation completes
            if let summary = lastInfoSummary {
                messages[assistantIndex].content += "\n\n_(\(summary))_"
            }
        } catch {
            if !Task.isCancelled {
                messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            }
        }

        isGenerating = false
    }
}
