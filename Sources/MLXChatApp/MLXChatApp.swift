import AppKit
import MLXChatCore
import OSLog
import SwiftUI

@main
struct MLXChatApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchCoordinator.self) private var appDelegate

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
    @FocusState private var focusedField: FocusedAppField?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel, focusedField: $focusedField)
                .frame(width: 280)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ChatPaneView(viewModel: viewModel, focusedField: $focusedField)
        }
        .background(WindowActivationView())
        .onAppear {
            viewModel.configure(baseURLText: storedBaseURL, selectedModel: storedSelectedModel)
            AppWindowActivator.activateAfterWindowCreation()
            focusComposerAfterLaunch()
        }
        .onChange(of: viewModel.baseURLText) { value in
            storedBaseURL = value
        }
        .onChange(of: viewModel.selectedModel) { value in
            storedSelectedModel = value
        }
    }

    private func focusComposerAfterLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            focusedField = .composer
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: ChatAppViewModel
    let focusedField: FocusState<FocusedAppField?>.Binding

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
                    .focused(focusedField, equals: .providerURL)

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

            ConversationListView(viewModel: viewModel)

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
                            ForEach(viewModel.models) { model in
                                ModelRow(
                                    model: model,
                                    isSelected: model.id == viewModel.selectedModel
                                ) {
                                    viewModel.selectModel(model.id)
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

struct ConversationListView: View {
    @ObservedObject var viewModel: ChatAppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conversations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    viewModel.newConversation()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Chat")
                .disabled(viewModel.isSending)
            }

            if viewModel.conversationSummaries.isEmpty {
                Text("No saved chats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.conversationSummaries) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == viewModel.activeConversationID,
                                selectAction: {
                                    viewModel.selectConversation(conversation.id)
                                },
                                deleteAction: {
                                    viewModel.deleteConversation(conversation.id)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool
    let selectAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: selectAction) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(conversation.selectedModel.isEmpty ? "No model" : conversation.selectedModel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete Chat")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ModelRow: View {
    let model: ProviderModelMetadata
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.primaryDisplayName)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let secondaryText = model.secondaryDisplayText {
                        Text(secondaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ModelTagRow(model: model)
                }

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

struct ModelTagRow: View {
    let model: ProviderModelMetadata

    var body: some View {
        FlowLayout(spacing: 4) {
            CapabilityBadge(capability: model.capability)

            ForEach(model.displayTags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(width: width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> (height: CGFloat, width: CGFloat) {
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth > 0, currentWidth + size.width > width {
                totalHeight += currentHeight + spacing
                maxWidth = max(maxWidth, currentWidth - spacing)
                currentWidth = 0
                currentHeight = 0
            }
            currentWidth += size.width + spacing
            currentHeight = max(currentHeight, size.height)
        }

        totalHeight += currentHeight
        maxWidth = max(maxWidth, currentWidth - spacing)
        return (totalHeight, maxWidth)
    }
}

struct CapabilityBadge: View {
    let capability: ProviderModelCapability

    var body: some View {
        Text(capability.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColour)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var foregroundColour: Color {
        switch capability {
        case .chatText:
            return .blue
        case .diffusionText:
            return .purple
        case .unsupported:
            return .orange
        }
    }

    private var backgroundColour: Color {
        foregroundColour.opacity(0.12)
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
    let focusedField: FocusState<FocusedAppField?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(viewModel: viewModel)

            Divider()

            TranscriptView(
                messages: viewModel.messages,
                isSending: viewModel.isSending,
                transcriptRevision: viewModel.transcriptRevision
            )

            if let modelNotice = viewModel.selectedModelNotice {
                Divider()
                ModelNoticeBanner(message: modelNotice)
            }

            if let errorMessage = viewModel.errorMessage {
                Divider()
                ErrorBanner(message: errorMessage)
            }

            Divider()

            ComposerView(viewModel: viewModel, focusedField: focusedField)
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

                Text(viewModel.selectedModelSubtitle)
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
    let transcriptRevision: Int

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
            .onChange(of: transcriptRevision) { _ in
                guard let lastID = messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
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

                if message.content.isEmpty, message.isStreaming {
                    Text("Streaming reply...")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MessageContentText(message: message)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if message.didFail {
                    Text("Reply interrupted")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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

struct MessageContentText: View {
    let message: ChatDisplayMessage

    var body: some View {
        Text(renderedContent)
    }

    private var renderedContent: AttributedString {
        (try? ChatMessagePresentation.renderedContent(role: message.role, content: message.content))
            ?? AttributedString(message.content)
    }
}

struct ComposerView: View {
    @ObservedObject var viewModel: ChatAppViewModel
    let focusedField: FocusState<FocusedAppField?>.Binding

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $viewModel.draftMessage, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isSending)
                .focused(focusedField, equals: .composer)
                .onSubmit {
                    submitDraft()
                }

            Button {
                submitDraft()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!viewModel.canSend)
        }
        .padding(18)
    }

    private func submitDraft() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.sendMessage()
        }
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

struct ModelNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)

            Text(message)
                .font(.callout)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.1))
    }
}

@MainActor
final class ChatAppViewModel: ObservableObject {
    private static let appLogger = Logger(subsystem: "MLXChat", category: "app")
    private static let chatLogger = Logger(subsystem: "MLXChat", category: "chat")

    @Published var baseURLText = "http://127.0.0.1:8123"
    @Published var healthState: ProviderHealthState = .unknown
    @Published var models: [ProviderModelMetadata] = []
    @Published var selectedModel = ""
    @Published var messages: [ChatDisplayMessage] = []
    @Published var conversationSummaries: [ConversationSummary] = []
    @Published var activeConversationID: UUID?
    @Published var transcriptRevision = 0
    @Published var draftMessage = ""
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var isSending = false

    private var hasConfigured = false
    private let conversationStore = ConversationStore()
    private var activeConversation: StoredConversation?
    private var saveTask: Task<Void, Never>?

    private var catalog: ProviderModelCatalog {
        ProviderModelCatalog(models: models)
    }

    var selectedModelSubtitle: String {
        guard let model = catalog.model(id: selectedModel) else {
            return baseURLText
        }
        if let resolvedModel = model.resolvedModel {
            return "\(resolvedModel) - \(baseURLText)"
        }
        return "\(model.capability.displayName) - \(baseURLText)"
    }

    var selectedModelNotice: String? {
        guard let model = catalog.model(id: selectedModel) else { return nil }
        if let reason = model.capability.unsupportedReason {
            return "This model cannot be used for chat: \(reason)"
        }
        if model.capability == .diffusionText {
            return "Text diffusion model selected. Responses are still text and use the same chat transcript."
        }
        return nil
    }

    var canSend: Bool {
        !isSending
            && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModel.isEmpty
            && LocalProviderURLValidator.providerURL(from: baseURLText) != nil
            && catalog.canSend(with: selectedModel)
    }

    func configure(baseURLText: String, selectedModel: String) {
        guard !hasConfigured else { return }
        hasConfigured = true
        self.baseURLText = baseURLText
        self.selectedModel = selectedModel
        loadInitialConversation(providerBaseURL: baseURLText, selectedModel: selectedModel)
        Self.appLogger.notice("App configured baseURL=\(self.safeBaseURLDescription(from: baseURLText), privacy: .public) persistedModel=\(selectedModel, privacy: .public)")
        logAppNotice("App configured baseURL=\(self.safeBaseURLDescription(from: baseURLText)) persistedModel=\(selectedModel)")

        Task {
            await refreshProvider()
        }
    }

    func refreshProvider() async {
        guard let baseURL = LocalProviderURLValidator.providerURL(from: baseURLText) else {
            healthState = .invalid
            models = []
            errorMessage = "Provider URL must be localhost."
            Self.appLogger.error("Provider refresh blocked invalidBaseURL=\(self.safeBaseURLDescription(from: self.baseURLText), privacy: .public)")
            logAppError("Provider refresh blocked invalidBaseURL=\(self.safeBaseURLDescription(from: self.baseURLText))")
            return
        }

        isRefreshing = true
        healthState = .checking
        errorMessage = nil
        Self.appLogger.notice("Provider refresh started baseURL=\(ProviderLogSanitizer.safeBaseURLDescription(baseURL), privacy: .public)")
        logAppNotice("Provider refresh started baseURL=\(ProviderLogSanitizer.safeBaseURLDescription(baseURL))")

        let client = ProviderClient(baseURL: baseURL, timeout: 10)
        do {
            let health = try await client.health()
            healthState = health.isSuccess ? .healthy : .disconnected
            Self.appLogger.notice("Provider health status=\(health.statusCode, privacy: .public) healthy=\(health.isSuccess, privacy: .public)")
            logAppNotice("Provider health status=\(health.statusCode) healthy=\(health.isSuccess)")

            let catalog = try await fetchModelCatalog(using: client)
            models = catalog.models
            selectedModel = catalog.defaultSelection(persistedSelection: selectedModel)
            persistActiveConversation()
            Self.appLogger.notice("Provider refresh finished models=\(self.models.count, privacy: .public) selectedModel=\(self.selectedModel, privacy: .public)")
            logAppNotice("Provider refresh finished models=\(self.models.count) selectedModel=\(self.selectedModel)")
        } catch {
            healthState = .disconnected
            models = []
            errorMessage = error.localizedDescription
            Self.appLogger.error("Provider refresh failed error=\(error.localizedDescription, privacy: .public)")
            logAppError("Provider refresh failed error=\(error.localizedDescription)")
        }

        isRefreshing = false
    }

    func selectModel(_ modelID: String) {
        selectedModel = modelID
        persistActiveConversation()
        let capability = catalog.model(id: modelID)?.capability.displayName ?? "Unknown"
        Self.appLogger.notice("Model selected id=\(modelID, privacy: .public) capability=\(capability, privacy: .public)")
        logAppNotice("Model selected id=\(modelID) capability=\(capability)")
    }

    func newConversation() {
        guard !isSending else { return }
        do {
            let conversation = try conversationStore.createConversation(
                providerBaseURL: baseURLText,
                selectedModel: selectedModel
            )
            applyConversation(conversation)
            conversationSummaries = try conversationStore.loadSummaries()
            errorMessage = nil
            Self.chatLogger.notice("Conversation created id=\(conversation.id.uuidString, privacy: .public)")
            logChatNotice("Conversation created id=\(conversation.id.uuidString)")
        } catch {
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Conversation create failed error=\(error.localizedDescription, privacy: .public)")
            logChatError("Conversation create failed error=\(error.localizedDescription)")
        }
    }

    func selectConversation(_ conversationID: UUID) {
        guard !isSending else { return }
        do {
            let conversation = try conversationStore.loadConversation(id: conversationID)
            applyConversation(conversation)
            conversationSummaries = try conversationStore.loadSummaries()
            errorMessage = nil
            Self.chatLogger.notice("Conversation selected id=\(conversationID.uuidString, privacy: .public)")
            logChatNotice("Conversation selected id=\(conversationID.uuidString)")
        } catch {
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Conversation select failed id=\(conversationID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            logChatError("Conversation select failed id=\(conversationID.uuidString) error=\(error.localizedDescription)")
        }
    }

    func deleteConversation(_ conversationID: UUID) {
        guard !isSending else { return }
        do {
            try conversationStore.deleteConversation(id: conversationID)
            conversationSummaries = try conversationStore.loadSummaries()
            if activeConversationID == conversationID {
                if let nextConversation = try conversationSummaries.first.map({ try conversationStore.loadConversation(id: $0.id) }) {
                    applyConversation(nextConversation)
                } else {
                    let conversation = try conversationStore.createConversation(
                        providerBaseURL: baseURLText,
                        selectedModel: selectedModel
                    )
                    applyConversation(conversation)
                    conversationSummaries = try conversationStore.loadSummaries()
                }
            }
            Self.chatLogger.notice("Conversation deleted id=\(conversationID.uuidString, privacy: .public)")
            logChatNotice("Conversation deleted id=\(conversationID.uuidString)")
        } catch {
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Conversation delete failed id=\(conversationID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            logChatError("Conversation delete failed id=\(conversationID.uuidString) error=\(error.localizedDescription)")
        }
    }

    func sendMessage() async {
        let prompt = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let baseURL = LocalProviderURLValidator.providerURL(from: baseURLText) else {
            errorMessage = "Provider URL must be localhost."
            Self.chatLogger.error("Send blocked invalidBaseURL=\(self.safeBaseURLDescription(from: self.baseURLText), privacy: .public)")
            logChatError("Send blocked invalidBaseURL=\(self.safeBaseURLDescription(from: self.baseURLText))")
            return
        }
        guard !selectedModel.isEmpty else {
            errorMessage = "Select a model."
            Self.chatLogger.error("Send blocked noModelSelected")
            logChatError("Send blocked noModelSelected")
            return
        }
        guard catalog.canSend(with: selectedModel) else {
            errorMessage = catalog.model(id: selectedModel)?.capability.unsupportedReason
                ?? "Selected model cannot be used for text chat."
            Self.chatLogger.error("Send blocked unsupportedModel=\(self.selectedModel, privacy: .public) reason=\(self.errorMessage ?? "unknown", privacy: .public)")
            logChatError("Send blocked unsupportedModel=\(self.selectedModel) reason=\(self.errorMessage ?? "unknown")")
            return
        }

        errorMessage = nil
        isSending = true

        let originalModel = selectedModel
        let modelForSend = await resolveModelForSend(prompt: prompt, baseURL: baseURL)
        if modelForSend != selectedModel {
            selectedModel = modelForSend
        }

        let userMessage = ChatDisplayMessage(role: "user", content: prompt)
        messages.append(userMessage)
        draftMessage = ""
        let transcript = messages.map { ChatTranscriptMessage(role: $0.role, content: $0.content) }

        let assistantMessageID = UUID()
        messages.append(
            ChatDisplayMessage(
                id: assistantMessageID,
                role: "assistant",
                content: "",
                isStreaming: true
            )
        )
        transcriptRevision += 1
        persistActiveConversation()

        let client = ProviderClient(baseURL: baseURL, timeout: 60)
        do {
            let capability = catalog.model(id: modelForSend)?.capability.displayName ?? "Unknown"
            Self.chatLogger.notice("Send started model=\(modelForSend, privacy: .public) originalModel=\(originalModel, privacy: .public) capability=\(capability, privacy: .public) transcriptMessages=\(self.messages.count, privacy: .public) promptCharacters=\(prompt.count, privacy: .public)")
            logChatNotice("Send started model=\(modelForSend) originalModel=\(originalModel) capability=\(capability) transcriptMessages=\(self.messages.count) promptCharacters=\(prompt.count)")
            var replyCharacters = 0
            for try await delta in client.streamChat(model: modelForSend, messages: transcript) {
                guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                    continue
                }
                if !delta.content.isEmpty {
                    messages[index].content += delta.content
                    replyCharacters += delta.content.count
                    transcriptRevision += 1
                    persistActiveConversation(debounced: true)
                }
            }
            if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                messages[index].isStreaming = false
                messages[index].didFail = false
            }
            transcriptRevision += 1
            persistActiveConversation()
            Self.chatLogger.notice("Send finished model=\(modelForSend, privacy: .public) status=stream replyCharacters=\(replyCharacters, privacy: .public)")
            logChatNotice("Send finished model=\(modelForSend) status=stream replyCharacters=\(replyCharacters)")
        } catch {
            if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                messages[index].isStreaming = false
                messages[index].didFail = true
            }
            transcriptRevision += 1
            persistActiveConversation()
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Send failed model=\(self.selectedModel, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            logChatError("Send failed model=\(self.selectedModel) error=\(error.localizedDescription)")
        }

        isSending = false
    }

    private func resolveModelForSend(prompt: String, baseURL: URL) async -> String {
        let adviceClient = ProviderClient(baseURL: baseURL, timeout: 1.5)
        return await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: selectedModel,
            latestPrompt: prompt,
            catalog: catalog,
            baseURL: baseURL,
            adviceProvider: { input, selectedModel in
                try await adviceClient.fetchModeAdvice(input: input, selectedModel: selectedModel)
            },
            userDecision: { prompt in
                self.confirmModeSwitch(prompt)
            }
        )
    }

    private func confirmModeSwitch(_ prompt: ModeAdviceSwitchPrompt) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Switch modes?"

        var details = [
            "Current model: \(prompt.currentModel)",
            "Suggested mode: \(prompt.suggestedMode)",
        ]
        if let confidence = prompt.confidencePercent {
            details.append("Confidence: \(confidence)%")
        }
        if let reason = prompt.reason, !reason.isEmpty {
            details.append("Reason: \(reason)")
        }
        alert.informativeText = details.joined(separator: "\n")
        alert.addButton(withTitle: "Use \(prompt.suggestedModel)")
        alert.addButton(withTitle: "Keep \(prompt.currentModel)")

        return alert.runModal() == .alertFirstButtonReturn
    }

    func clearTranscript() {
        messages = []
        transcriptRevision += 1
        errorMessage = nil
        persistActiveConversation()
        Self.chatLogger.notice("Transcript cleared")
        logChatNotice("Transcript cleared")
    }

    private func loadInitialConversation(providerBaseURL: String, selectedModel: String) {
        do {
            conversationSummaries = try conversationStore.loadSummaries()
            if let firstSummary = conversationSummaries.first {
                applyConversation(try conversationStore.loadConversation(id: firstSummary.id))
                return
            }

            let conversation = try conversationStore.createConversation(
                providerBaseURL: providerBaseURL,
                selectedModel: selectedModel
            )
            applyConversation(conversation)
            conversationSummaries = try conversationStore.loadSummaries()
        } catch {
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Conversation load failed error=\(error.localizedDescription, privacy: .public)")
            logChatError("Conversation load failed error=\(error.localizedDescription)")
        }
    }

    private func applyConversation(_ conversation: StoredConversation) {
        saveTask?.cancel()
        activeConversation = conversation
        activeConversationID = conversation.id
        baseURLText = conversation.providerBaseURL
        selectedModel = conversation.selectedModel
        messages = conversation.messages
        transcriptRevision += 1
    }

    private func persistActiveConversation(debounced: Bool = false) {
        saveTask?.cancel()
        if debounced {
            saveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    self?.persistActiveConversationNow()
                }
            }
            return
        }
        persistActiveConversationNow()
    }

    private func persistActiveConversationNow() {
        guard var conversation = activeConversation else { return }
        conversation.providerBaseURL = baseURLText
        conversation.selectedModel = selectedModel
        conversation.messages = messages
        do {
            try conversationStore.save(conversation)
            activeConversation = conversation
            conversationSummaries = try conversationStore.loadSummaries()
        } catch {
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Conversation save failed id=\(conversation.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            logChatError("Conversation save failed id=\(conversation.id.uuidString) error=\(error.localizedDescription)")
        }
    }

    private func fetchModelCatalog(using client: ProviderClient) async throws -> ProviderModelCatalog {
        let advertisedModels = try await client.fetchModelList().models
        do {
            let metadata = try await client.fetchModelMetadata().models
            Self.appLogger.notice("Building model catalog advertised=\(advertisedModels.count, privacy: .public) metadata=\(metadata.count, privacy: .public)")
            logAppNotice("Building model catalog advertised=\(advertisedModels.count) metadata=\(metadata.count)")
            return ProviderModelCatalog(advertisedModels: advertisedModels, metadata: metadata)
        } catch {
            Self.appLogger.warning("Model metadata unavailable; falling back to advertised models only error=\(error.localizedDescription, privacy: .public)")
            logAppWarning("Model metadata unavailable; falling back to advertised models only error=\(error.localizedDescription)")
            return ProviderModelCatalog(models: advertisedModels)
        }
    }

    private func safeBaseURLDescription(from text: String) -> String {
        guard let url = URL(string: text) else {
            return "<invalid-url>"
        }
        return ProviderLogSanitizer.safeBaseURLDescription(url)
    }

    private func logAppNotice(_ message: String) {
        MLXChatFileLogger.notice(category: "app", message)
    }

    private func logAppWarning(_ message: String) {
        MLXChatFileLogger.warning(category: "app", message)
    }

    private func logAppError(_ message: String) {
        MLXChatFileLogger.error(category: "app", message)
    }

    private func logChatNotice(_ message: String) {
        MLXChatFileLogger.notice(category: "chat", message)
    }

    private func logChatError(_ message: String) {
        MLXChatFileLogger.error(category: "chat", message)
    }
}


enum FocusedAppField: Hashable {
    case providerURL
    case composer
}

final class AppLaunchCoordinator: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppWindowActivator.activateAfterWindowCreation()
    }
}

enum AppWindowActivator {
    static func activateAfterWindowCreation() {
        DispatchQueue.main.async {
            activate(window: NSApp.keyWindow ?? NSApp.windows.first)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            activate(window: NSApp.keyWindow ?? NSApp.windows.first)
        }
    }

    static func activate(window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard let window else { return }
        window.level = .normal
        window.deminiaturize(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

struct WindowActivationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ActivatingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ActivatingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            AppWindowActivator.activate(window: window)
        }
    }
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
