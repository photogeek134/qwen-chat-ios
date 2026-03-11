import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    modelStatusBar(geo: geo)
                    Divider()

                    // MARK: - Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.messages.filter { !$0.isContinuationPrompt }) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, horizontalPadding(geo: geo))
                            .padding(.vertical, 12)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }

                    // MARK: - Truncation banner
                    if viewModel.isTruncated {
                        ContinueBanner(
                            tokenBudget: ChatViewModel.maxTokensPerPass,
                            onContinue: { viewModel.continueGeneration() },
                            onDismiss: { viewModel.isTruncated = false }
                        )
                        .padding(.horizontal, horizontalPadding(geo: geo))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isTruncated)
                    }

                    Divider()

                    // MARK: - Input area
                    VStack(spacing: 0) {
                        MessageInputView(viewModel: viewModel)
                            .padding(.horizontal, horizontalPadding(geo: geo))
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        KeyboardShortcutHint()
                            .padding(.bottom, 8)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("QwenChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        // Ensure the layout shrinks correctly when the software keyboard appears
        // on iPhone. On iPad this has no effect since the keyboard floats.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            await viewModel.loadModel()
        }
    }

    // MARK: - Status bar

    private func modelStatusBar(geo: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            // State icon
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if viewModel.modelContainer != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if viewModel.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "cpu").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedModel.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Group {
                    if viewModel.isLoading {
                        Text(viewModel.loadingStatus)
                    } else if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(.orange)
                    } else {
                        Text(viewModel.selectedModel.approximateSizeDescription)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Only show badges when there's enough horizontal room
            if geo.size.width > 400 {
                Text("\(ChatViewModel.maxTokensPerPass) tok")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            if geo.size.width > 320 {
                Text("~\(Int(DeviceMemory.bucketGB.rounded())) GB")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, horizontalPadding(geo: geo))
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
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
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

    /// Horizontal padding that responds to the actual available width from
    /// GeometryReader rather than just the size class. This handles all cases:
    /// - iPhone portrait/landscape
    /// - iPad full screen portrait/landscape
    /// - iPad Split View (1/3, 1/2, 2/3 column widths)
    /// - iPad Slide Over
    private func horizontalPadding(geo: GeometryProxy) -> CGFloat {
        let width = geo.size.width
        switch width {
        case ..<400:
            // Slide Over, Split View 1/3, or iPhone — minimal padding
            return 12
        case 400..<600:
            // Split View 1/2, iPhone landscape, or small iPad
            return 16
        case 600..<900:
            // Split View 2/3, iPad portrait
            return 24
        default:
            // Full-screen iPad — constrain to a comfortable reading width
            return max(24, (width - 720) / 2)
        }
    }
}

#Preview {
    ContentView()
}
