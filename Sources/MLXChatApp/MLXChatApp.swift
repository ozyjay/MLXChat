import AppKit
import MLXChatCore
import OSLog
import SwiftUI

@main
struct MLXChatApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchCoordinator.self) private var appDelegate
    @AppStorage("MLXChat.messageFontSize") private var messageFontSize = 14.0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Increase Chat Text Size") {
                    messageFontSize = min(messageFontSize + 1, 24)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Chat Text Size") {
                    messageFontSize = max(messageFontSize - 1, 11)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Chat Text Size") {
                    messageFontSize = 14
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}

struct ContentView: View {
    @AppStorage("MLXChat.baseURL") private var storedBaseURL = "http://127.0.0.1:8123"
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
            viewModel.configure(baseURLText: storedBaseURL)
            AppWindowActivator.activateAfterWindowCreation()
            focusComposerAfterLaunch()
        }
        .onChange(of: viewModel.baseURLText) { value in
            storedBaseURL = value
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

                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
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
                isSending: viewModel.isSending
            )

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
                Text(viewModel.routingStatus.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.routingStatus.subtitle(baseURLText: viewModel.baseURLText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                guard TranscriptAutoScrollPolicy.shouldScrollToLatest(for: .messageCountChanged) else {
                    return
                }
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
    @AppStorage("MLXChat.messageFontSize") private var messageFontSize = 14.0

    private var isUser: Bool {
        message.role == "user"
    }

    private var displayContent: String {
        guard !isUser else { return message.content }
        return ChatMessagePresentation.normalizedAssistantContent(content: message.content).content
    }

    private var displayReasoning: String? {
        guard !isUser else { return nil }
        let normalized = ChatMessagePresentation.normalizedAssistantContent(
            content: message.content,
            reasoning: message.reasoning
        )
        return normalized.reasoning
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

                if !isUser,
                   let reasoning = displayReasoning,
                   !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ThinkingPanel(
                        reasoning: reasoning,
                        baseFontSize: messageFontSize
                    )
                }

                if displayContent.isEmpty, message.isStreaming {
                    Text("Streaming reply...")
                        .font(.system(size: messageFontSize))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MessageContentText(message: message, displayContent: displayContent)
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
            .frame(maxWidth: isUser ? 620 : .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser {
                EmptyView()
            }
        }
    }
}

struct ThinkingPanel: View {
    let reasoning: String
    let baseFontSize: Double

    var body: some View {
        DisclosureGroup {
            MarkdownBlockView(
                blocks: ChatMessagePresentation.contentBlocks(
                    role: "assistant",
                    content: reasoning
                ),
                baseFontSize: baseFontSize,
                isReasoning: true
            )
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .imageScale(.small)
                Text("Thinking")
                    .font(.system(size: max(baseFontSize - 1, 11), weight: .semibold))
                Text("internal reasoning")
                    .font(.system(size: max(baseFontSize - 3, 10)))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .tint(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MessageContentText: View {
    let message: ChatDisplayMessage
    let displayContent: String
    @AppStorage("MLXChat.messageFontSize") private var messageFontSize = 14.0

    var body: some View {
        if message.role == "assistant" {
            MarkdownBlockView(
                blocks: ChatMessagePresentation.contentBlocks(role: message.role, content: displayContent),
                baseFontSize: messageFontSize
            )
        } else {
            Text(displayContent)
                .font(.system(size: messageFontSize))
        }
    }
}

struct MarkdownBlockView: View {
    let blocks: [ChatContentBlock]
    let baseFontSize: Double
    var isReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ChatContentBlock) -> some View {
        switch block.kind {
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.system(size: baseFontSize))
        case .heading:
            Text(inlineMarkdown(block.text))
                .font(.system(size: headingFontSize(for: block.level), weight: .semibold))
                .padding(.top, 2)
        case .bulletListItem, .unorderedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("-")
                    .font(.system(size: baseFontSize))
                Text(inlineMarkdown(block.text))
                    .font(.system(size: baseFontSize))
            }
        case .numberedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(block.ordinal ?? 1).")
                    .font(.system(size: baseFontSize))
                    .monospacedDigit()
                Text(inlineMarkdown(block.text))
                    .font(.system(size: baseFontSize))
            }
        case .code:
            Text(block.text)
                .font(.system(size: max(baseFontSize - 1, 11), design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? ChatMessagePresentation.renderedContent(role: "assistant", content: text))
            ?? AttributedString(text)
    }

    private func headingFontSize(for level: Int?) -> Double {
        switch level ?? 3 {
        case 1:
            return baseFontSize + 8
        case 2:
            return baseFontSize + 5
        case 3:
            return baseFontSize + 3
        default:
            return baseFontSize + 1
        }
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

struct ProviderRoutingStatus {
    var requestedAlias = "mlx-ask"
    var effectiveModel: String?
    var mode: String?
    var routingState: String?
    var fallbackReason: String?
    var adviceReason: String?
    var adviceConfidence: Double?

    var title: String {
        guard let effectiveModel, !effectiveModel.isEmpty else {
            return "Dashboard routing"
        }
        return effectiveModel
    }

    func subtitle(baseURLText: String) -> String {
        var parts: [String] = []
        if let mode, !mode.isEmpty {
            parts.append("\(mode.capitalized) route")
        } else {
            parts.append("Provider routing")
        }
        parts.append("via \(requestedAlias)")
        if let fallbackReason, !fallbackReason.isEmpty {
            parts.append(fallbackReason)
        } else if let routingState, !routingState.isEmpty, routingState != "direct" {
            parts.append(routingState.replacingOccurrences(of: "_", with: " "))
        } else if let adviceReason, !adviceReason.isEmpty {
            parts.append(adviceReason)
        }
        parts.append(baseURLText)
        return parts.joined(separator: " - ")
    }
}

@MainActor
final class ChatAppViewModel: ObservableObject {
    private static let appLogger = Logger(subsystem: "MLXChat", category: "app")
    private static let chatLogger = Logger(subsystem: "MLXChat", category: "chat")

    @Published var baseURLText = "http://127.0.0.1:8123"
    @Published var healthState: ProviderHealthState = .unknown
    @Published var models: [ProviderModelMetadata] = []
    @Published var requestModelAlias = "mlx-ask"
    @Published var routingStatus = ProviderRoutingStatus()
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

    var canSend: Bool {
        !isSending
            && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requestModelAlias.isEmpty
            && LocalProviderURLValidator.providerURL(from: baseURLText) != nil
            && catalog.canSend(with: requestModelAlias)
    }

    func configure(baseURLText: String) {
        guard !hasConfigured else { return }
        hasConfigured = true
        self.baseURLText = baseURLText
        loadInitialConversation(providerBaseURL: baseURLText)
        Self.appLogger.notice("App configured baseURL=\(self.safeBaseURLDescription(from: baseURLText), privacy: .public)")
        logAppNotice("App configured baseURL=\(self.safeBaseURLDescription(from: baseURLText))")

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
            requestModelAlias = preferredRoutingAlias(in: catalog)
            updateRoutingStatus(alias: requestModelAlias)
            persistActiveConversation()
            Self.appLogger.notice("Provider refresh finished models=\(self.models.count, privacy: .public) routingAlias=\(self.requestModelAlias, privacy: .public)")
            logAppNotice("Provider refresh finished models=\(self.models.count) routingAlias=\(self.requestModelAlias)")
        } catch {
            healthState = .disconnected
            models = []
            errorMessage = error.localizedDescription
            Self.appLogger.error("Provider refresh failed error=\(error.localizedDescription, privacy: .public)")
            logAppError("Provider refresh failed error=\(error.localizedDescription)")
        }

        isRefreshing = false
    }

    func newConversation() {
        guard !isSending else { return }
        do {
            let conversation = try conversationStore.createConversation(
                providerBaseURL: baseURLText,
                selectedModel: ""
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
                        selectedModel: ""
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
        guard !requestModelAlias.isEmpty else {
            errorMessage = "Dashboard did not advertise a sendable routing alias."
            Self.chatLogger.error("Send blocked noRoutingAlias")
            logChatError("Send blocked noRoutingAlias")
            return
        }
        guard catalog.canSend(with: requestModelAlias) else {
            errorMessage = catalog.model(id: requestModelAlias)?.capability.unsupportedReason
                ?? "Dashboard routing alias cannot be used for text chat."
            Self.chatLogger.error("Send blocked unsupportedRoutingAlias=\(self.requestModelAlias, privacy: .public) reason=\(self.errorMessage ?? "unknown", privacy: .public)")
            logChatError("Send blocked unsupportedRoutingAlias=\(self.requestModelAlias) reason=\(self.errorMessage ?? "unknown")")
            return
        }

        errorMessage = nil
        isSending = true

        let baselineAlias = requestModelAlias
        let modelForSend = await resolveAliasForSend(prompt: prompt, baseURL: baseURL)
        requestModelAlias = modelForSend
        updateRoutingStatus(alias: modelForSend)

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
            Self.chatLogger.notice("Send started routingAlias=\(modelForSend, privacy: .public) baselineAlias=\(baselineAlias, privacy: .public) capability=\(capability, privacy: .public) transcriptMessages=\(self.messages.count, privacy: .public) promptCharacters=\(prompt.count, privacy: .public)")
            logChatNotice("Send started routingAlias=\(modelForSend) baselineAlias=\(baselineAlias) capability=\(capability) transcriptMessages=\(self.messages.count) promptCharacters=\(prompt.count)")
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
                if let reasoning = delta.reasoning, !reasoning.isEmpty {
                    if let existingReasoning = messages[index].reasoning,
                       !existingReasoning.isEmpty {
                        messages[index].reasoning = "\(existingReasoning)\n\n\(reasoning)"
                    } else {
                        messages[index].reasoning = reasoning
                    }
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
            Self.chatLogger.notice("Send finished routingAlias=\(modelForSend, privacy: .public) status=stream replyCharacters=\(replyCharacters, privacy: .public)")
            logChatNotice("Send finished routingAlias=\(modelForSend) status=stream replyCharacters=\(replyCharacters)")
        } catch {
            if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                messages[index].isStreaming = false
                messages[index].didFail = true
            }
            transcriptRevision += 1
            persistActiveConversation()
            errorMessage = error.localizedDescription
            Self.chatLogger.error("Send failed routingAlias=\(self.requestModelAlias, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            logChatError("Send failed routingAlias=\(self.requestModelAlias) error=\(error.localizedDescription)")
        }

        isSending = false
    }

    private func resolveAliasForSend(prompt: String, baseURL: URL) async -> String {
        let baselineAlias = requestModelAlias
        guard catalog.supportsModeAdvice(baseURL: baseURL) else {
            return baselineAlias
        }

        let adviceClient = ProviderClient(baseURL: baseURL, timeout: 1.5)
        do {
            let advice = try await adviceClient.fetchModeAdvice(
                input: prompt,
                selectedModel: baselineAlias
            )
            let suggestedAlias = ModeAdviceCoordinator.alias(for: advice.suggestedMode)
            let alias = suggestedAlias.flatMap { catalog.canSend(with: $0) ? $0 : nil } ?? baselineAlias
            updateRoutingStatus(alias: alias, advice: advice)
            return alias
        } catch {
            return baselineAlias
        }
    }

    func clearTranscript() {
        messages = []
        transcriptRevision += 1
        errorMessage = nil
        persistActiveConversation()
        Self.chatLogger.notice("Transcript cleared")
        logChatNotice("Transcript cleared")
    }

    private func loadInitialConversation(providerBaseURL: String) {
        do {
            conversationSummaries = try conversationStore.loadSummaries()
            if let firstSummary = conversationSummaries.first {
                applyConversation(try conversationStore.loadConversation(id: firstSummary.id))
                return
            }

            let conversation = try conversationStore.createConversation(
                providerBaseURL: providerBaseURL,
                selectedModel: ""
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
        conversation.selectedModel = ""
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

    private func preferredRoutingAlias(in catalog: ProviderModelCatalog) -> String {
        for alias in ["mlx-ask", "mlx-plan", "mlx-coding"] where catalog.canSend(with: alias) {
            return alias
        }
        return catalog.models.first { $0.isSendableTextModel }?.id ?? ""
    }

    private func updateRoutingStatus(alias: String, advice: ProviderModeAdvice? = nil) {
        let model = catalog.model(id: alias)
        routingStatus = ProviderRoutingStatus(
            requestedAlias: alias,
            effectiveModel: model?.effectiveModel ?? model?.resolvedModel,
            mode: model?.role ?? advice?.suggestedMode,
            routingState: model?.routingState,
            fallbackReason: model?.fallbackReason,
            adviceReason: advice?.reason,
            adviceConfidence: advice?.confidence
        )
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
