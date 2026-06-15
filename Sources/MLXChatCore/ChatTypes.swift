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

    public init(model: String, assistantText: String, statusCode: Int, rawBody: Data) {
        self.model = model
        self.assistantText = assistantText
        self.statusCode = statusCode
        self.rawBody = rawBody
    }
}
