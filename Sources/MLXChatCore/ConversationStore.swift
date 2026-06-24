import Foundation

public struct ConversationSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let updatedAt: Date
    public let selectedModel: String

    public init(id: UUID, title: String, updatedAt: Date, selectedModel: String) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.selectedModel = selectedModel
    }
}

public struct StoredConversation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var providerBaseURL: String
    public var selectedModel: String
    public var messages: [ChatDisplayMessage]

    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        providerBaseURL: String,
        selectedModel: String,
        messages: [ChatDisplayMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerBaseURL = providerBaseURL
        self.selectedModel = selectedModel
        self.messages = messages
    }
}

public struct ConversationStore {
    private let applicationSupportDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        applicationSupportDirectory: URL = MLXChatFileLogger.defaultApplicationSupportDirectory(),
        fileManager: FileManager = .default
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func createConversation(
        providerBaseURL: String,
        selectedModel: String,
        now: Date = Date()
    ) throws -> StoredConversation {
        let conversation = StoredConversation(
            title: "New Chat",
            createdAt: now,
            updatedAt: now,
            providerBaseURL: providerBaseURL,
            selectedModel: selectedModel
        )
        try saveConversationFile(conversation)
        var summaries = try loadSummaries().filter { $0.id != conversation.id }
        summaries.append(summary(from: conversation))
        try writeIndex(summaries: sortedSummaries(summaries))
        return conversation
    }

    public func loadSummaries() throws -> [ConversationSummary] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return sortedSummaries(try decoder.decode([ConversationSummary].self, from: data))
    }

    public func loadConversation(id: UUID) throws -> StoredConversation {
        let data = try Data(contentsOf: conversationURL(id: id))
        var conversation = try decoder.decode(StoredConversation.self, from: data)
        conversation.messages = conversation.messages.map { message in
            var message = message
            message.isStreaming = false
            return message
        }
        return conversation
    }

    public func save(_ conversation: StoredConversation, now: Date = Date()) throws {
        var conversation = conversation
        conversation.updatedAt = now
        conversation.title = title(for: conversation)
        conversation.messages = conversation.messages.map { message in
            var message = message
            message.isStreaming = false
            return message
        }

        try saveConversationFile(conversation)
        var summaries = try loadSummaries().filter { $0.id != conversation.id }
        summaries.append(summary(from: conversation))
        try writeIndex(summaries: sortedSummaries(summaries))
    }

    public func deleteConversation(id: UUID) throws {
        if fileManager.fileExists(atPath: conversationURL(id: id).path) {
            try fileManager.removeItem(at: conversationURL(id: id))
        }
        try writeIndex(summaries: try loadSummaries().filter { $0.id != id })
    }

    private var conversationsDirectory: URL {
        applicationSupportDirectory.appending(path: "Conversations", directoryHint: .isDirectory)
    }

    private var indexURL: URL {
        conversationsDirectory.appending(path: "index.json")
    }

    private func conversationURL(id: UUID) -> URL {
        conversationsDirectory.appending(path: "\(id.uuidString).json")
    }

    private func saveConversationFile(_ conversation: StoredConversation) throws {
        try fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(conversation)
        try data.write(to: conversationURL(id: conversation.id), options: .atomic)
    }

    private func writeIndex(summaries: [ConversationSummary]) throws {
        try fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(summaries)
        try data.write(to: indexURL, options: .atomic)
    }

    private func summary(from conversation: StoredConversation) -> ConversationSummary {
        ConversationSummary(
            id: conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            selectedModel: conversation.selectedModel
        )
    }

    private func sortedSummaries(_ summaries: [ConversationSummary]) -> [ConversationSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func title(for conversation: StoredConversation) -> String {
        guard conversation.title == "New Chat" else { return conversation.title }
        guard let firstUserMessage = conversation.messages.first(where: { $0.role == "user" }) else {
            return "New Chat"
        }

        let firstLine = firstUserMessage.content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstLine.isEmpty else { return "New Chat" }
        if firstLine.count <= 48 {
            return firstLine
        }
        return String(firstLine.prefix(48))
    }
}
