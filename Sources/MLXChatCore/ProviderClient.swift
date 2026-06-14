import Foundation

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
        case let .invalidURL(path):
            return "Cannot construct a valid URL for path: \(path)"
        case let .requestFailed(error):
            return "Request failed: \(error.localizedDescription)"
        case let .unexpectedStatusCode(code, message):
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
        return (200..<300).contains(statusCode)
    }
}

public struct ProviderClient {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(baseURL: URL, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    public init(baseURL: URL, timeout: TimeInterval) {
        self.init(baseURL: baseURL, transport: URLSessionHTTPTransport(timeout: timeout))
    }

    public func health() async throws -> HTTPResponse {
        try await request(path: "/health", method: .get)
    }

    public func fetchModels() async throws -> (models: [String], statusCode: Int) {
        let response = try await request(path: "/v1/models", method: .get)
        guard response.isSuccess else {
            throw ProviderClientError.unexpectedStatusCode(response.statusCode, responseText(response.body))
        }

        let payload = try jsonDecoder.decode(ModelsPayload.self, from: response.body)
        let modelNames = payload.data.map { $0.id }
        return (modelNames, response.statusCode)
    }

    public func chatCompletions(model: String, prompt: String = "Hello", stream: Bool = false) async throws -> HTTPResponse {
        let body = ChatCompletionPayload(
            model: model,
            messages: [ChatMessage(role: "user", content: prompt)],
            stream: stream
        )
        return try await request(path: "/v1/chat/completions", method: .post, body: body)
    }

    public func responses(model: String, prompt: String = "Hello", stream: Bool = false) async throws -> HTTPResponse {
        let body = ResponsesPayload(
            model: model,
            input: prompt,
            stream: stream
        )
        return try await request(path: "/v1/responses", method: .post, body: body)
    }

    private func request(path: String, method: HTTPMethod, body: (any Encodable)? = nil) async throws -> HTTPResponse {
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            do {
                request.httpBody = try jsonEncoder.encode(AnyEncodable(value: body))
            } catch {
                throw ProviderClientError.requestFailed(error)
            }
        }

        do {
            let (data, response) = try await transport.send(request)
            return HTTPResponse(statusCode: response.statusCode, body: data)
        } catch {
            throw ProviderClientError.requestFailed(error)
        }
    }

    private func buildURL(path: String) throws -> URL {
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "\(base)\(normalizedPath)") else {
            throw ProviderClientError.invalidURL(path)
        }
        return url
    }

    private func responseText(_ data: Data) -> String? {
        let text = String(data: data, encoding: .utf8)
        return text
    }

    private struct ModelsPayload: Decodable {
        let data: [ProviderModel]
    }

    private struct ProviderModel: Decodable {
        let id: String
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatCompletionPayload: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
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
