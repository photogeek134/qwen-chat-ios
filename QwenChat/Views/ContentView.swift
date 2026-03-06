import SwiftUI

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @State private var messageText = ""
    @State private var selectedImage: UIImage?
    @State private var scrollToBottom = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToLatest(proxy: proxy)
                    }
                    .onChange(of: viewModel.messages.last?.content) { _, _ in
                        scrollToLatest(proxy: proxy)
                    }
                }

                // Loading indicator
                if viewModel.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.loadProgress)
                            .padding(.horizontal)
                        Text(viewModel.loadingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }

                // Input bar
                MessageInputView(
                    messageText: $messageText,
                    selectedImage: $selectedImage,
                    showCamera: viewModel.selectedModel.isVisionModel,
                    isGenerating: viewModel.isGenerating,
                    onSend: sendMessage,
                    onStop: { viewModel.stopGeneration() }
                )
            }
            .navigationTitle("QwenChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AppModel.allCases) { model in
                            Button {
                                Task { await viewModel.switchModel(to: model) }
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    if model == viewModel.selectedModel {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedModel.displayName)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadModel()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                print("[DEBUG] App entering background — stopping generation and releasing model")
                viewModel.releaseModel()
            case .active:
                if viewModel.modelContainer == nil {
                    Task { await viewModel.loadModel() }
                }
            default:
                break
            }
        }
    }

    private func sendMessage() {
        let text = messageText
        let image = selectedImage
        messageText = ""
        selectedImage = nil
        viewModel.sendMessage(text: text, image: image)
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        if let lastMessage = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

#Preview {
    ContentView()
}
