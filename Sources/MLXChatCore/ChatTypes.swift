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
    public var requestedModel: String?
    public var responseModel: String?
    public var finishReason: String?
    public var usageState: MLXStreamUsageState?
    public let createdAt: Date
    public var isStreaming: Bool
    public var didFail: Bool

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        reasoning: String? = nil,
        requestedModel: String? = nil,
        responseModel: String? = nil,
        finishReason: String? = nil,
        usageState: MLXStreamUsageState? = nil,
        createdAt: Date = Date(),
        isStreaming: Bool = false,
        didFail: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.requestedModel = requestedModel
        self.responseModel = responseModel
        self.finishReason = finishReason
        self.usageState = usageState
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.didFail = didFail
    }
}

public struct MLXStreamUsageState: Codable, Equatable, Sendable {
    public let phase: String
    public let model: String?
    public let context: MLXStreamUsageContext
    public let tokens: MLXStreamUsageTokens

    public var hasDisplayableUsageData: Bool {
        phase == "completed"
            || context.limitTokens != nil
            || context.usedTokens != nil
            || context.remainingTokens != nil
            || context.usageRatio != nil
            || tokens.inputTokens != nil
            || tokens.outputTokens != nil
            || tokens.totalTokens != nil
    }

    public init(
        phase: String,
        model: String? = nil,
        context: MLXStreamUsageContext = MLXStreamUsageContext(),
        tokens: MLXStreamUsageTokens = MLXStreamUsageTokens()
    ) {
        self.phase = phase
        self.model = model
        self.context = context
        self.tokens = tokens
    }
}

public struct MLXStreamUsageContext: Codable, Equatable, Sendable {
    public let limitTokens: Int?
    public let usedTokens: Int?
    public let remainingTokens: Int?
    public let usageRatio: Double?

    public init(
        limitTokens: Int? = nil,
        usedTokens: Int? = nil,
        remainingTokens: Int? = nil,
        usageRatio: Double? = nil
    ) {
        self.limitTokens = limitTokens
        self.usedTokens = usedTokens
        self.remainingTokens = remainingTokens
        self.usageRatio = usageRatio
    }

    private enum CodingKeys: String, CodingKey {
        case limitTokens = "limit_tokens"
        case usedTokens = "used_tokens"
        case remainingTokens = "remaining_tokens"
        case usageRatio = "usage_ratio"
    }
}

public struct MLXStreamUsageTokens: Codable, Equatable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
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
