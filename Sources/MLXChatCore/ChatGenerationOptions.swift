import Foundation

public enum TextDiffusionGenerationMode: String, Codable, CaseIterable, Equatable, Sendable {
    case diffusion
    case linearSpec = "linear_spec"
    case autoregressive
}

public struct TextDiffusionOptions: Codable, Equatable, Sendable {
    public var mode: TextDiffusionGenerationMode?
    public var steps: Int?
    public var blockLength: Int?
    public var threshold: Double?
    public var algorithm: String?
    public var seed: Int?

    public init(mode: TextDiffusionGenerationMode? = nil, steps: Int? = nil, blockLength: Int? = nil, threshold: Double? = nil, algorithm: String? = nil, seed: Int? = nil) {
        self.mode = mode
        self.steps = steps
        self.blockLength = blockLength
        self.threshold = threshold
        self.algorithm = algorithm
        self.seed = seed
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case steps
        case blockLength = "block_length"
        case threshold
        case algorithm
        case seed
    }
}

public struct ChatGenerationOptions: Equatable, Sendable {
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var minP: Double?
    public var stopSequences: [String]?
    public var diffusion: TextDiffusionOptions?

    public init(maxTokens: Int? = nil, temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil, minP: Double? = nil, stopSequences: [String]? = nil, diffusion: TextDiffusionOptions? = nil) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.stopSequences = stopSequences
        self.diffusion = diffusion
    }

    public static let providerDefaults = ChatGenerationOptions()
}

public struct ChatTokenUsage: Codable, Equatable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct TextDiffusionResultMetadata: Codable, Equatable, Sendable {
    public let mode: String?
    public let steps: Int?
    public let blockLength: Int?
    public let nfe: Int?

    private enum CodingKeys: String, CodingKey {
        case mode
        case steps
        case blockLength = "block_length"
        case nfe
    }
}
