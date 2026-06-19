import Foundation
import OSLog

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

public enum ProviderClientError: Error, LocalizedError {
    case nonHTTPResponse
    case invalidURL(String)
    case requestFailed(Error)
    case unexpectedStatusCode(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            return "Received a non-HTTP response."
        case .invalidURL(let path):
            return "Cannot construct a valid URL for path: \(path)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .unexpectedStatusCode(let code, let message):
            if let message, !message.isEmpty {
                return "Unexpected status code \(code): \(message)"
            }
            return "Unexpected status code: \(code)"
        }
    }
}

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderClientError.nonHTTPResponse
        }
        return (data, httpResponse)
    }
}

public struct HTTPResponse {
    public let statusCode: Int
    public let body: Data

    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}

public struct ProviderClient {
    private static let logger = Logger(subsystem: "MLXChat", category: "provider")

    private let baseURL: URL
    private let transport: HTTPTransport
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(baseURL: URL, transport: HTTPTransport) {
        let normalizedBaseURL =
            LocalProviderURLValidator.providerURL(from: baseURL.absoluteString)
            ?? baseURL

        let safeBaseURLDescription =
            ProviderLogSanitizer.safeBaseURLDescription(normalizedBaseURL)

        self.baseURL = normalizedBaseURL
        self.transport = transport
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()

        Self.logger.debug(
            "ProviderClient created baseURL=\(safeBaseURLDescription, privacy: .public)"
        )
        Self.logFileDebug(
            "ProviderClient created baseURL=\(safeBaseURLDescription)"
        )
    }

    public init(baseURL: URL, timeout: TimeInterval) {
        self.init(baseURL: baseURL, transport: URLSessionHTTPTransport(timeout: timeout))
    }

    public func health() async throws -> HTTPResponse {
        try await request(path: "/health", method: .get)
    }

    public func fetchModels() async throws -> (models: [String], statusCode: Int) {
        let result = try await fetchModelList()
        return (result.models.map(\.id), result.statusCode)
    }

    public func fetchModelList() async throws -> (models: [ProviderModelMetadata], statusCode: Int)
    {
        let response = try await request(path: "/v1/models", method: .get)
        guard response.isSuccess else {
            throw ProviderClientError.unexpectedStatusCode(
                response.statusCode, responseText(response.body))
        }

        let payload = try jsonDecoder.decode(ModelsPayload.self, from: response.body)
        let models = payload.data.map(\.metadata)
        Self.logger.notice(
            "Fetched advertised models count=\(models.count, privacy: .public) status=\(response.statusCode, privacy: .public)"
        )
        Self.logFileNotice(
            "Fetched advertised models count=\(models.count) status=\(response.statusCode)")
        return (models, response.statusCode)
    }

    public func fetchModelMetadata() async throws -> (
        models: [ProviderModelMetadata], statusCode: Int
    ) {
        do {
            return try await fetchModelMetadata(path: "/provider/v1/models")
        } catch {
            guard shouldFallbackToLegacyMetadataRoute(error) else {
                throw error
            }
            Self.logger.warning(
                "Canonical provider metadata unavailable; falling back to legacy /api/v0/models error=\(error.localizedDescription, privacy: .public)"
            )
            Self.logFileWarning(
                "Canonical provider metadata unavailable; falling back to legacy /api/v0/models error=\(error.localizedDescription)"
            )
            return try await fetchModelMetadata(path: "/api/v0/models")
        }
    }

    public func chatCompletions(
        model: String,
        prompt: String = "Hello",
        stream: Bool = false,
        options: ChatGenerationOptions = .providerDefaults
    ) async throws -> HTTPResponse {
        let body = ChatCompletionPayload(
            model: model,
            messages: [ChatTranscriptMessage(role: "user", content: prompt)],
            stream: stream,
            options: options
        )
        return try await request(path: "/v1/chat/completions", method: .post, body: body)
    }

    public func completeChat(
        model: String,
        messages: [ChatTranscriptMessage],
        options: ChatGenerationOptions = .providerDefaults
    ) async throws -> ChatCompletionResult {
        let body = ChatCompletionPayload(
            model: model,
            messages: messages,
            stream: false,
            options: options
        )
        let response = try await request(path: "/v1/chat/completions", method: .post, body: body)
        guard response.isSuccess else {
            throw ProviderClientError.unexpectedStatusCode(
                response.statusCode, responseText(response.body))
        }

        let payload = try jsonDecoder.decode(
            ChatCompletionResponsePayload.self, from: response.body)
        let firstChoice = payload.choices.first
        let assistantText = firstChoice?.message?.content ?? firstChoice?.text ?? ""
        Self.logger.notice(
            "Completed chat model=\(model, privacy: .public) resolvedModel=\(payload.model ?? model, privacy: .public) status=\(response.statusCode, privacy: .public) replyCharacters=\(assistantText.count, privacy: .public)"
        )
        Self.logFileNotice(
            "Completed chat model=\(model) resolvedModel=\(payload.model ?? model) status=\(response.statusCode) replyCharacters=\(assistantText.count)"
        )

        return ChatCompletionResult(
            model: payload.model ?? model,
            assistantText: assistantText,
            statusCode: response.statusCode,
            rawBody: response.body,
            finishReason: firstChoice?.finishReason,
            usage: payload.usage,
            diffusion: payload.diffusion
        )
    }

    public func fetchModeAdvice(input: String, selectedModel: String) async throws
        -> ProviderModeAdvice
    {
        let body = ModeAdviceRequestPayload(input: input, selectedModel: selectedModel)
        let response = try await request(
            path: "/provider/v1/mode-advice", method: .post, body: body)
        guard response.isSuccess else {
            throw ProviderClientError.unexpectedStatusCode(
                response.statusCode, responseText(response.body))
        }
        return try jsonDecoder.decode(ProviderModeAdvice.self, from: response.body)
    }

    public func responses(model: String, prompt: String = "Hello", stream: Bool = false)
        async throws -> HTTPResponse
    {
        let body = ResponsesPayload(model: model, input: prompt, stream: stream)
        return try await request(path: "/v1/responses", method: .post, body: body)
    }

    private func fetchModelMetadata(path: String) async throws -> (
        models: [ProviderModelMetadata], statusCode: Int
    ) {
        let response = try await request(path: path, method: .get)
        guard response.isSuccess else {
            throw ProviderClientError.unexpectedStatusCode(
                response.statusCode, responseText(response.body))
        }

        let payload = try jsonDecoder.decode(ModelMetadataPayload.self, from: response.body)
        let metadata = payload.data.map(\.metadata)
        Self.logger.notice(
            "Fetched model metadata count=\(metadata.count, privacy: .public) status=\(response.statusCode, privacy: .public)"
        )
        Self.logFileNotice(
            "Fetched model metadata path=\(path) count=\(metadata.count) status=\(response.statusCode)"
        )
        return (metadata, response.statusCode)
    }

    private func shouldFallbackToLegacyMetadataRoute(_ error: Error) -> Bool {
        if case ProviderClientError.unexpectedStatusCode(404, _) = error {
            return true
        }
        if case ProviderClientError.requestFailed = error {
            return true
        }
        return false
    }

    private func request(path: String, method: HTTPMethod, body: (any Encodable)? = nil)
        async throws -> HTTPResponse
    {
        let url = try buildURL(path: path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.logger.debug(
            "Provider request start method=\(method.rawValue, privacy: .public) path=\(path, privacy: .public)"
        )
        Self.logFileDebug("Provider request start method=\(method.rawValue) path=\(path)")

        if let body {
            do {
                urlRequest.httpBody = try jsonEncoder.encode(AnyEncodable(value: body))
            } catch {
                Self.logger.error(
                    "Provider request encode failed method=\(method.rawValue, privacy: .public) path=\(path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                Self.logFileError(
                    "Provider request encode failed method=\(method.rawValue) path=\(path) error=\(error.localizedDescription)"
                )
                throw ProviderClientError.requestFailed(error)
            }
        }

        do {
            let (data, response) = try await transport.send(urlRequest)
            if (200..<300).contains(response.statusCode) {
                Self.logger.debug(
                    "Provider request finished method=\(method.rawValue, privacy: .public) path=\(path, privacy: .public) status=\(response.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)"
                )
                Self.logFileDebug(
                    "Provider request finished method=\(method.rawValue) path=\(path) status=\(response.statusCode) bytes=\(data.count)"
                )
            } else {
                Self.logger.error(
                    "Provider request non-success method=\(method.rawValue, privacy: .public) path=\(path, privacy: .public) status=\(response.statusCode, privacy: .public) body=\"\(ProviderLogSanitizer.responseSnippet(data), privacy: .public)\""
                )
                Self.logFileError(
                    "Provider request non-success method=\(method.rawValue) path=\(path) status=\(response.statusCode) body=\"\(ProviderLogSanitizer.responseSnippet(data))\""
                )
            }
            return HTTPResponse(statusCode: response.statusCode, body: data)
        } catch let error as ProviderClientError {
            throw error
        } catch {
            Self.logger.error(
                "Provider request failed method=\(method.rawValue, privacy: .public) path=\(path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            Self.logFileError(
                "Provider request failed method=\(method.rawValue) path=\(path) error=\(error.localizedDescription)"
            )
            throw ProviderClientError.requestFailed(error)
        }
    }

    private func buildURL(path: String) throws -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard
            let url = URL(string: normalizedPath, relativeTo: baseURL.appending(path: ""))?
                .absoluteURL
        else {
            throw ProviderClientError.invalidURL(path)
        }
        return url
    }

    private func responseText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    private static func logFileNotice(_ message: String) {
        MLXChatFileLogger.notice(category: "provider", message)
    }

    private static func logFileWarning(_ message: String) {
        MLXChatFileLogger.warning(category: "provider", message)
    }

    private static func logFileError(_ message: String) {
        MLXChatFileLogger.error(category: "provider", message)
    }

    private static func logFileDebug(_ message: String) {
        MLXChatFileLogger.debug(category: "provider", message)
    }

    private struct ModelsPayload: Decodable {
        let data: [ProviderModel]
    }

    private struct ProviderModel: Decodable {
        let id: String
        let resolvedModel: String?
        let role: String?
        let ownedBy: String?
        let publisher: String?
        let arch: String?
        let quantization: String?
        let generationType: String?
        let modelFamily: String?
        let compatibilityType: String?
        let state: String?
        let maxContextLength: Int?
        let maxOutputTokens: Int?
        let runtime: String?
        let modelType: String?
        let supportsStreaming: Bool?
        let supportedGenerationModes: [String]?

        var metadata: ProviderModelMetadata {
            ProviderModelMetadata(
                id: id,
                capability: capability,
                state: state,
                resolvedModel: resolvedModel,
                role: role,
                ownedBy: ownedBy,
                publisher: publisher,
                arch: arch,
                quantization: quantization,
                generationType: generationType,
                modelFamily: modelFamily,
                compatibilityType: compatibilityType,
                maxContextLength: maxContextLength,
                maxOutputTokens: maxOutputTokens,
                runtime: runtime,
                modelType: modelType,
                supportsStreaming: supportsStreaming,
                supportedGenerationModes: supportedGenerationModes
            )
        }

        private var capability: ProviderModelCapability {
            if state == "unsupported" {
                return .unsupported(reason: "Unsupported by provider")
            }
            if state == "not_installed" {
                return .unsupported(reason: "Model is not installed")
            }
            if generationType == "text", modelFamily == "diffusion_text" {
                return .diffusionText
            }
            return .chatText
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case resolvedModel = "resolved_model"
            case role
            case ownedBy = "owned_by"
            case publisher
            case arch
            case quantization
            case generationType = "generation_type"
            case modelFamily = "model_family"
            case compatibilityType = "compatibility_type"
            case state
            case maxContextLength = "max_context_length"
            case maxOutputTokens = "max_output_tokens"
            case runtime
            case modelType = "model_type"
            case supportsStreaming = "supports_streaming"
            case supportedGenerationModes = "supported_generation_modes"
        }
    }

    private struct ModelMetadataPayload: Decodable {
        let data: [ProviderModelMetadataPayload]
    }

    private struct ProviderModelMetadataPayload: Decodable {
        let id: String
        let type: String?
        let resolvedModel: String?
        let role: String?
        let ownedBy: String?
        let publisher: String?
        let arch: String?
        let quantization: String?
        let generationType: String?
        let modelFamily: String?
        let compatibilityType: String?
        let state: String?
        let maxContextLength: Int?
        let maxOutputTokens: Int?
        let runtime: String?
        let modelType: String?
        let supportsStreaming: Bool?
        let supportedGenerationModes: [String]?
        let reason: String?
        let unsupportedReason: String?
        let notInstalledReason: String?

        var metadata: ProviderModelMetadata {
            ProviderModelMetadata(
                id: id,
                capability: capability,
                state: state,
                resolvedModel: resolvedModel,
                role: role,
                ownedBy: ownedBy,
                publisher: publisher,
                arch: arch,
                quantization: quantization,
                generationType: generationType,
                modelFamily: modelFamily,
                compatibilityType: compatibilityType,
                maxContextLength: maxContextLength,
                maxOutputTokens: maxOutputTokens,
                runtime: runtime,
                modelType: modelType,
                supportsStreaming: supportsStreaming,
                supportedGenerationModes: supportedGenerationModes
            )
        }

        private var capability: ProviderModelCapability {
            if state == "unsupported" {
                return .unsupported(
                    reason: unsupportedReason ?? reason ?? "Unsupported by provider")
            }
            if state == "not_installed" {
                return .unsupported(
                    reason: notInstalledReason ?? reason ?? "Model is not installed")
            }
            if generationType == "text", modelFamily == "diffusion_text" {
                return .diffusionText
            }
            return .chatText
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case type
            case resolvedModel = "resolved_model"
            case role
            case ownedBy = "owned_by"
            case publisher
            case arch
            case quantization
            case generationType = "generation_type"
            case modelFamily = "model_family"
            case compatibilityType = "compatibility_type"
            case state
            case maxContextLength = "max_context_length"
            case maxOutputTokens = "max_output_tokens"
            case runtime
            case modelType = "model_type"
            case supportsStreaming = "supports_streaming"
            case supportedGenerationModes = "supported_generation_modes"
            case reason
            case unsupportedReason = "unsupported_reason"
            case notInstalledReason = "not_installed_reason"
        }
    }

    private struct ChatCompletionPayload: Encodable {
        let model: String
        let messages: [ChatTranscriptMessage]
        let stream: Bool
        let maxTokens: Int?
        let temperature: Double?
        let topP: Double?
        let topK: Int?
        let minP: Double?
        let stop: [String]?
        let mlxDiffusion: TextDiffusionOptions?

        init(
            model: String, messages: [ChatTranscriptMessage], stream: Bool,
            options: ChatGenerationOptions
        ) {
            self.model = model
            self.messages = messages
            self.stream = stream
            self.maxTokens = options.maxTokens
            self.temperature = options.temperature
            self.topP = options.topP
            self.topK = options.topK
            self.minP = options.minP
            self.stop = options.stopSequences
            self.mlxDiffusion = options.diffusion
        }

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case maxTokens = "max_tokens"
            case temperature
            case topP = "top_p"
            case topK = "top_k"
            case minP = "min_p"
            case stop
            case mlxDiffusion = "mlx_diffusion"
        }
    }

    private struct ModeAdviceRequestPayload: Encodable {
        let input: String
        let selectedModel: String

        private enum CodingKeys: String, CodingKey {
            case input
            case selectedModel = "selected_model"
        }
    }

    private struct ChatCompletionResponsePayload: Decodable {
        let model: String?
        let choices: [ChatCompletionChoice]
        let usage: ChatTokenUsage?
        let diffusion: TextDiffusionResultMetadata?
    }

    private struct ChatCompletionChoice: Decodable {
        let message: ChatCompletionMessage?
        let text: String?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case text
            case finishReason = "finish_reason"
        }
    }

    private struct ChatCompletionMessage: Decodable {
        let content: String?
    }

    private struct ResponsesPayload: Encodable {
        let model: String
        let input: String
        let stream: Bool
    }
}

private struct AnyEncodable: Encodable {
    private let value: any Encodable

    init(value: any Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
