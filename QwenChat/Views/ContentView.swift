import SwiftUI

struct ContentView: View {
@State private var viewModel = ChatViewModel()
@Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            modelStatusBar
            Divider()

            // MARK: - Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Filter out the silent "Continue." prompts so the
                        // conversation transcript looks seamless.
                        ForEach(viewModel.messages.filter { !$0.isContinuationPrompt }) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // MARK: - Truncation banner (shown between scroll area and input)
            if viewModel.isTruncated {
                ContinueBanner(
                    tokenBudget: ChatViewModel.maxTokensPerPass,
                    onContinue: {
                        viewModel.continueGeneration()
                    },
                    onDismiss: {
                        viewModel.isTruncated = false
                    }
                )
                .padding(.horizontal, horizontalPadding)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isTruncated)
            }

            Divider()

            // MARK: - Input area
            VStack(spacing: 0) {
                MessageInputView(viewModel: viewModel)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                KeyboardShortcutHint()
                    .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
        .navigationTitle("QwenChat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }
    .task {
        await viewModel.loadModel()
    }
}

// MARK: - Status bar

private var modelStatusBar: some View {
    HStack(spacing: 12) {
        Group {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if viewModel.modelContainer != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if viewModel.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "cpu").foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.selectedModel.displayName)
                .font(.subheadline.weight(.medium))
            Group {
                if viewModel.isLoading {
                    Text(viewModel.loadingStatus)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                } else {
                    Text(viewModel.selectedModel.approximateSizeDescription)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Token budget badge — useful to set user expectations
        Text("\(ChatViewModel.maxTokensPerPass) tok max")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)

        Text("~\(Int(DeviceMemory.bucketGB.rounded())) GB RAM")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, 10)
    .background(.bar)
}

// MARK: - Toolbar

@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
        Menu {
            Section("Available on this device") {
                ForEach(QwenModel.supportedModels) { model in
                    Button {
                        Task { await viewModel.switchModel(to: model) }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                Text(model.approximateSizeDescription)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            if model == viewModel.selectedModel {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            let unsupported = QwenModel.allCases.filter { !$0.isSupported }
            if !unsupported.isEmpty {
                Section("Requires more RAM") {
                    ForEach(unsupported) { model in
                        Label {
                            VStack(alignment: .leading) {
                                Text(model.displayName).foregroundStyle(.secondary)
                                Text(model.unsupportedReason)
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        }
                        .disabled(true)
                    }
                }
            }
        } label: {
            Label("Model", systemImage: "square.3.layers.3d")
        }
    }

    ToolbarItem(placement: .navigationBarTrailing) {
        Button {
            viewModel.messages.removeAll()
        } label: {
            Image(systemName: "trash")
        }
        .disabled(viewModel.messages.isEmpty)
    }
}

// MARK: - Adaptive layout

private var horizontalPadding: CGFloat {
    if horizontalSizeClass == .regular {
        return max(24, (UIScreen.main.bounds.width - 720) / 2)
    }
    return 16
}


}

#Preview {
ContentView()
}
