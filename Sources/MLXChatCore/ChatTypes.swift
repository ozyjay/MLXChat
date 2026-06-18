import Foundation

public struct ChatTranscriptMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
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

    public init(
        model: String,
        assistantText: String,
        statusCode: Int,
        rawBody: Data,
        finishReason: String? = nil,
        usage: ChatTokenUsage? = nil,
        diffusion: TextDiffusionResultMetadata? = nil
    ) {
        self.model = model
        self.assistantText = assistantText
        self.statusCode = statusCode
        self.rawBody = rawBody
        self.finishReason = finishReason
        self.usage = usage
        self.diffusion = diffusion
    }
}
