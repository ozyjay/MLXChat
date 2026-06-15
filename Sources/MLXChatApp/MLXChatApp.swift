import MLXChatCore
import SwiftUI

@main
struct MLXChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @AppStorage("MLXChat.baseURL") private var storedBaseURL = "http://127.0.0.1:8123"
    @AppStorage("MLXChat.selectedModel") private var storedSelectedModel = ""
    @StateObject private var viewModel = ChatAppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel)
                .frame(width: 280)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ChatPaneView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.configure(baseURLText: storedBaseURL, selectedModel: storedSelectedModel)
        }
        .onChange(of: viewModel.baseURLText) { value in
            storedBaseURL = value
        }
        .onChange(of: viewModel.selectedModel) { value in
            storedSelectedModel = value
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: ChatAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MLXChat")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Base URL", text: $viewModel.baseURLText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    HealthBadge(state: viewModel.healthState)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.refreshProvider()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Models")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if viewModel.models.isEmpty {
                    Text("No models")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.models, id: \.self) { model in
                                ModelRow(
                                    model: model,
                                    isSelected: model == viewModel.selectedModel
                                ) {
                                    viewModel.selectedModel = model
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }
}

struct ModelRow: View {
    let model: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(model)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct HealthBadge: View {
    let state: ProviderHealthState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.colour)
                .frame(width: 8, height: 8)

            Text(state.title)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ChatPaneView: View {
    @ObservedObject var viewModel: ChatAppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(viewModel: viewModel)

            Divider()

            TranscriptView(messages: viewModel.messages, isSending: viewModel.isSending)

            if let errorMessage = viewModel.errorMessage {
                Divider()
                ErrorBanner(message: errorMessage)
            }

            Divider()

            ComposerView(viewModel: viewModel)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ChatHeaderView: View {
    @ObservedObject var viewModel: ChatAppViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedModel.isEmpty ? "No model selected" : viewModel.selectedModel)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.baseURLText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                viewModel.clearTranscript()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.messages.isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct TranscriptView: View {
    let messages: [ChatDisplayMessage]
    let isSending: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        Text("No messages yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for reply")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(18)
            }
            .onChange(of: messages.count) { _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatDisplayMessage

    private var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(isUser ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 80)
            }
        }
    }
}

struct ComposerView: View {
    @ObservedObject var viewModel: ChatAppViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $viewModel.draftMessage, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isSending)

            Button {
                Task {
                    await viewModel.sendMessage()
                }
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.canSend)
        }
        .padding(18)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

@MainActor
final class ChatAppViewModel: ObservableObject {
    @Published var baseURLText = "http://127.0.0.1:8123"
    @Published var healthState: ProviderHealthState = .unknown
    @Published var models: [String] = []
    @Published var selectedModel = ""
    @Published var messages: [ChatDisplayMessage] = []
    @Published var draftMessage = ""
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var isSending = false

    private var hasConfigured = false

    var canSend: Bool {
        !isSending
            && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModel.isEmpty
            && LocalProviderURLValidator.providerURL(from: baseURLText) != nil
    }

    func configure(baseURLText: String, selectedModel: String) {
        guard !hasConfigured else { return }
        hasConfigured = true
        self.baseURLText = baseURLText
        self.selectedModel = selectedModel

        Task {
            await refreshProvider()
        }
    }

    func refreshProvider() async {
        guard let baseURL = LocalProviderURLValidator.providerURL(from: baseURLText) else {
            healthState = .invalid
            models = []
            errorMessage = "Provider URL must be localhost."
            return
        }

        isRefreshing = true
        healthState = .checking
        errorMessage = nil

        let client = ProviderClient(baseURL: baseURL, timeout: 10)
        do {
            let health = try await client.health()
            healthState = health.isSuccess ? .healthy : .disconnected

            let fetched = try await client.fetchModels().models
            models = fetched
            if !models.contains(selectedModel) {
                selectedModel = models.contains("mlx-ask") ? "mlx-ask" : (models.first ?? "")
            }
        } catch {
            healthState = .disconnected
            models = []
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func sendMessage() async {
        let prompt = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let baseURL = LocalProviderURLValidator.providerURL(from: baseURLText) else {
            errorMessage = "Provider URL must be localhost."
            return
        }
        guard !selectedModel.isEmpty else {
            errorMessage = "Select a model."
            return
        }

        let userMessage = ChatDisplayMessage(role: "user", content: prompt)
        messages.append(userMessage)
        draftMessage = ""
        errorMessage = nil
        isSending = true

        let client = ProviderClient(baseURL: baseURL, timeout: 60)
        do {
            let transcript = messages.map { ChatTranscriptMessage(role: $0.role, content: $0.content) }
            let result = try await client.completeChat(model: selectedModel, messages: transcript)
            messages.append(ChatDisplayMessage(role: "assistant", content: result.assistantText))
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    func clearTranscript() {
        messages = []
        errorMessage = nil
    }
}

struct ChatDisplayMessage: Equatable, Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

enum ProviderHealthState {
    case unknown
    case checking
    case healthy
    case disconnected
    case invalid

    var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking"
        case .healthy:
            return "Healthy"
        case .disconnected:
            return "Disconnected"
        case .invalid:
            return "Invalid"
        }
    }

    var colour: Color {
        switch self {
        case .unknown:
            return .secondary
        case .checking:
            return .yellow
        case .healthy:
            return .green
        case .disconnected:
            return .red
        case .invalid:
            return .orange
        }
    }
}
