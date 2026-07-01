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
        !phase.isEmpty
            || context.limitTokens != nil
            || context.usedTokens != nil
            || context.remainingTokens != nil
            || context.usageRatio != nil
            || tokens.inputTokens != nil
            || tokens.outputTokens != nil
            || tokens.totalTokens != nil
    }

    public var displayLines: [String] {
        var lines: [String] = []
        if phase == "started" {
            lines.append("Usage: streaming")
        } else if phase == "completed" {
            lines.append("Usage: completed")
        } else if !phase.isEmpty {
            lines.append("Usage: \(phase.replacingOccurrences(of: "_", with: " "))")
        }

        if let contextLine {
            lines.append(contextLine)
        }
        if let tokenLine {
            lines.append(tokenLine)
        }
        if lines == ["Usage: completed"] {
            lines[0] = "Usage: not reported by provider"
        }
        return lines
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

    private var contextLine: String? {
        switch (context.usedTokens, context.limitTokens, context.remainingTokens, context.usageRatio) {
        case let (used?, limit?, remaining?, ratio?):
            "Context: \(Self.format(used)) / \(Self.format(limit)) used (\(Self.percent(ratio))) - \(Self.format(remaining)) remaining"
        case let (used?, limit?, _, ratio?):
            "Context: \(Self.format(used)) / \(Self.format(limit)) used (\(Self.percent(ratio)))"
        case let (used?, limit?, remaining?, _):
            "Context: \(Self.format(used)) / \(Self.format(limit)) used - \(Self.format(remaining)) remaining"
        case let (used?, limit?, _, _):
            "Context: \(Self.format(used)) / \(Self.format(limit)) used"
        case let (_, limit?, remaining?, ratio?):
            "Context: \(Self.format(limit)) limit (\(Self.percent(ratio))) - \(Self.format(remaining)) remaining"
        case let (_, limit?, remaining?, _):
            "Context: \(Self.format(limit)) limit - \(Self.format(remaining)) remaining"
        case let (_, limit?, _, _):
            "Context: \(Self.format(limit)) limit"
        case let (used?, _, remaining?, ratio?):
            "Context: \(Self.format(used)) used (\(Self.percent(ratio))) - \(Self.format(remaining)) remaining"
        case let (used?, _, _, ratio?):
            "Context: \(Self.format(used)) used (\(Self.percent(ratio)))"
        case let (used?, _, remaining?, _):
            "Context: \(Self.format(used)) used - \(Self.format(remaining)) remaining"
        case let (used?, _, _, _):
            "Context: \(Self.format(used)) used"
        case let (_, _, remaining?, ratio?):
            "Context: \(Self.percent(ratio)) - \(Self.format(remaining)) remaining"
        case let (_, _, remaining?, _):
            "Context: \(Self.format(remaining)) remaining"
        case let (_, _, _, ratio?):
            "Context: \(Self.percent(ratio))"
        default:
            nil
        }
    }

    private var tokenLine: String? {
        let totalTokens = tokens.totalTokens
            ?? tokens.inputTokens.flatMap { input in
                tokens.outputTokens.map { output in input + output }
            }
        let estimatedPrefix = tokens.estimated == true ? "~" : ""
        let parts = [
            totalTokens.map { "\(estimatedPrefix)\(Self.format($0)) total" },
            tokens.inputTokens.map { "\(Self.format($0)) in" },
            tokens.outputTokens.map { "\(Self.format($0)) out" },
        ]
        .compactMap { $0 }

        guard !parts.isEmpty else { return nil }
        return "Tokens: \(parts.joined(separator: " / "))"
    }

    private static func format(_ value: Int) -> String {
        tokenFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func percent(_ ratio: Double) -> String {
        let percent = max(0, ratio * 100)
        return percentFormatter.string(from: NSNumber(value: percent / 100)) ?? "\(Int(percent.rounded()))%"
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()
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
    public let estimated: Bool?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        estimated: Bool? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.estimated = estimated
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case estimated
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
