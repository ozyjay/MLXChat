import Foundation

public struct ChatTranscriptMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatDisplayMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: String
    public var content: String
    public var reasoning: String?
    public let createdAt: Date
    public var isStreaming: Bool
    public var didFail: Bool

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        reasoning: String? = nil,
        createdAt: Date = Date(),
        isStreaming: Bool = false,
        didFail: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.didFail = didFail
    }
}

public struct ChatCompletionResult: Equatable, Sendable {
    public let model: String
    public let assistantText: String
    public let statusCode: Int
    public let rawBody: Data
    public let finishReason: String?
    public let usage: ChatTokenUsage?
    public let diffusion: TextDiffusionResultMetadata?
    public let reasoning: String?

    public init(
        model: String,
        assistantText: String,
        statusCode: Int,
        rawBody: Data,
        finishReason: String? = nil,
        usage: ChatTokenUsage? = nil,
        diffusion: TextDiffusionResultMetadata? = nil,
        reasoning: String? = nil
    ) {
        self.model = model
        self.assistantText = assistantText
        self.statusCode = statusCode
        self.rawBody = rawBody
        self.finishReason = finishReason
        self.usage = usage
        self.diffusion = diffusion
        self.reasoning = reasoning
    }
}

public enum TranscriptAutoScrollEvent: Equatable, Sendable {
    case messageCountChanged
    case transcriptRevisionChanged
}

public enum TranscriptAutoScrollPolicy {
    public static func shouldScrollToLatest(for event: TranscriptAutoScrollEvent) -> Bool {
        switch event {
        case .messageCountChanged:
            return true
        case .transcriptRevisionChanged:
            return false
        }
    }
}
