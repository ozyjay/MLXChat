import Foundation
import XCTest

@testable import MLXChatCore

final class CLIOptionsTests: XCTestCase {
    func testDefaults() throws {
        let options = try CLIOptions(arguments: [])
        XCTAssertEqual(options.baseURL.absoluteString, "http://127.0.0.1:8123")
        XCTAssertEqual(options.timeout, 10)
        XCTAssertFalse(options.outputJSON)
        XCTAssertTrue(options.runStreamingCheck)
        XCTAssertFalse(options.helpRequested)
    }

    func testParsingOverrides() throws {
        let options = try CLIOptions(
            arguments: [
                "--base-url", "http://127.0.0.1:9999",
                "--timeout", "12",
                "--json",
                "--no-stream",
            ]
        )
        XCTAssertEqual(options.baseURL.absoluteString, "http://127.0.0.1:9999")
        XCTAssertEqual(options.timeout, 12)
        XCTAssertTrue(options.outputJSON)
        XCTAssertFalse(options.runStreamingCheck)
    }

    func testUnknownArgumentThrows() {
        XCTAssertThrowsError(try CLIOptions(arguments: ["--unknown"])) { error in
            XCTAssertEqual(error as? CLIOptionsError, .unknownArgument("--unknown"))
        }
    }

    func testRelativeBaseURLThrows() {
        XCTAssertThrowsError(try CLIOptions(arguments: ["--base-url", "provider"])) { error in
            XCTAssertEqual(error as? CLIOptionsError, .invalidBaseURLError("provider"))
        }
    }

    func testUnsupportedBaseURLSchemeThrows() {
        XCTAssertThrowsError(try CLIOptions(arguments: ["--base-url", "file:///tmp/provider"])) { error in
            XCTAssertEqual(error as? CLIOptionsError, .invalidBaseURLError("file:///tmp/provider"))
        }
    }
}

final class FakeTransport: HTTPTransport {
    private let responses: [String: MockResponse]

    init(responses: [String: MockResponse]) {
        self.responses = responses
    }
}

final class SmokeTestRunnerTests: XCTestCase {
    func testSmokeRunnerPassesWithAllRoutes() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /health": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"status":"ok"}"#.utf8)
                ),
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-fast"},{"id":"mlx-phi"}]}"#
                            .utf8
                    )
                ),
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"#
                            .utf8
                    )
                ),
                "POST /v1/chat/completions stream=true": MockResponse(
                    statusCode: 200,
                    body: Data(#"data: {"object":"chat.completion","choices":[{"delta":{"content":"ok"}}]}\ndata: [DONE]"#.utf8)
                ),
                "POST /v1/responses": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"id":"resp","object":"responses","output":[{"type":"text","text":"ok"}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let runner = SmokeTestRunner(client: client)
        let report = await runner.run(includeStreamingCheck: true)

        XCTAssertEqual(report.checks.count, 5)
        XCTAssertTrue(report.allPassed)
    }

    func testSmokeRunnerCanSkipStreamingCheck() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /health": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"status":"ok"}"#.utf8)
                ),
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-fast"}]}"#
                            .utf8
                    )
                ),
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"#
                            .utf8
                    )
                ),
                "POST /v1/responses": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"id":"resp","object":"responses","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let runner = SmokeTestRunner(client: client)
        let report = await runner.run(includeStreamingCheck: false)

        XCTAssertEqual(report.checks.count, 4)
        XCTAssertTrue(report.allPassed)
        XCTAssertFalse(report.includeStreamingCheck)
    }
}

final class ProviderChatCompletionTests: XCTestCase {
    func testCompleteChatParsesAssistantMessageContent() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","model":"mlx-ask","choices":[{"index":0,"message":{"role":"assistant","content":"Hello from MLX."}}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.completeChat(
            model: "mlx-ask",
            messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
        )

        XCTAssertEqual(result.model, "mlx-ask")
        XCTAssertEqual(result.assistantText, "Hello from MLX.")
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertFalse(result.rawBody.isEmpty)
    }

    func testCompleteChatParsesTextFallback() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","choices":[{"index":0,"text":"Fallback text reply."}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.completeChat(
            model: "mlx-fast",
            messages: [ChatTranscriptMessage(role: "user", content: "Use fallback")]
        )

        XCTAssertEqual(result.model, "mlx-fast")
        XCTAssertEqual(result.assistantText, "Fallback text reply.")
        XCTAssertEqual(result.statusCode, 200)
    }

    func testCompleteChatThrowsForNonSuccessStatus() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 503,
                    body: Data(#"{"error":"provider unavailable"}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        do {
            _ = try await client.completeChat(
                model: "mlx-plan",
                messages: [ChatTranscriptMessage(role: "user", content: "Plan")]
            )
            XCTFail("Expected non-success chat response to throw.")
        } catch let error as ProviderClientError {
            XCTAssertEqual(
                error.localizedDescription,
                #"Unexpected status code 503: {"error":"provider unavailable"}"#
            )
        }
    }

    func testCompleteChatUsesChatCompletionsForTextDiffusionModels() async throws {
        let diffusionModel = "mlx-community/Nemotron-Labs-Diffusion-3B-4bit"
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(
                    #"{"id":"chat","model":"mlx-community/Nemotron-Labs-Diffusion-3B-4bit","choices":[{"index":0,"message":{"role":"assistant","content":"Diffusion text reply."}}]}"#
                        .utf8
                )
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.completeChat(
            model: diffusionModel,
            messages: [ChatTranscriptMessage(role: "user", content: "Draft a short note")]
        )

        XCTAssertEqual(result.model, diffusionModel)
        XCTAssertEqual(result.assistantText, "Diffusion text reply.")
        XCTAssertEqual(transport.requestPaths, ["/v1/chat/completions"])
        XCTAssertEqual(transport.requestMethods, ["POST"])
        XCTAssertEqual(transport.requestBodies.count, 1)
        XCTAssertTrue(transport.requestBodies[0].contains(#""model":"mlx-community\/Nemotron-Labs-Diffusion-3B-4bit""#))
        XCTAssertTrue(transport.requestBodies[0].contains(#""stream":false"#))
    }
}

final class ProviderModelMetadataTests: XCTestCase {
    func testFetchModelMetadataParsesNormalChatTextModel() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /api/v0/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"llm","generation_type":"text","model_family":"chat","state":"loaded"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.models, [
            ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
        ])
    }

    func testFetchModelMetadataParsesTextDiffusionModel() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /api/v0/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-community/DiffusionGemma","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"loaded"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()

        XCTAssertEqual(result.models.first?.capability, .diffusionText)
        XCTAssertTrue(result.models.first?.isSendableTextModel == true)
    }

    func testFetchModelMetadataParsesUnsupportedModelReason() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /api/v0/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-community/DiffusionGemma","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"unsupported","unsupported_reason":"Unsupported by installed mlx-lm: diffusion_gemma"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()

        XCTAssertEqual(
            result.models.first?.capability,
            .unsupported(reason: "Unsupported by installed mlx-lm: diffusion_gemma")
        )
        XCTAssertFalse(result.models.first?.isSendableTextModel ?? true)
    }

    func testModelCatalogPreservesMlxAskDefaultAndBlocksUnsupportedSend() {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(id: "mlx-community/DiffusionGemma", capability: .diffusionText, state: "loaded"),
                ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(
                    id: "mlx-community/Unsupported",
                    capability: .unsupported(reason: "Unsupported by installed runtime"),
                    state: "unsupported"
                ),
            ]
        )

        XCTAssertEqual(catalog.defaultSelection(persistedSelection: ""), "mlx-ask")
        XCTAssertEqual(catalog.defaultSelection(persistedSelection: "mlx-community/DiffusionGemma"), "mlx-community/DiffusionGemma")
        XCTAssertTrue(catalog.canSend(with: "mlx-ask"))
        XCTAssertTrue(catalog.canSend(with: "mlx-community/DiffusionGemma"))
        XCTAssertFalse(catalog.canSend(with: "mlx-community/Unsupported"))
    }

    func testModelCatalogFallsBackToV1ModelsAsChatText() {
        let catalog = ProviderModelCatalog(modelIDs: ["mlx-plan", "mlx-community/Tiny"])

        XCTAssertEqual(catalog.models.map(\.capability), [.chatText, .chatText])
        XCTAssertEqual(catalog.defaultSelection(persistedSelection: ""), "mlx-plan")
    }

    func testModelCatalogKeepsOnlyAdvertisedModelsWhenMetadataHasExtraRows() {
        let catalog = ProviderModelCatalog(
            advertisedModelIDs: [
                "mlx-ask",
                "mlx-community/Nemotron-Labs-Diffusion-3B-4bit",
            ],
            metadata: [
                ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(id: "Qwen/Qwen3-8B", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(
                    id: "mlx-community/Nemotron-Labs-Diffusion-3B-4bit",
                    capability: .diffusionText,
                    state: "loaded"
                ),
                ProviderModelMetadata(id: "mlx-community/gemma-4-12B-it-4bit", capability: .chatText, state: "loaded"),
            ]
        )

        XCTAssertEqual(catalog.models.map(\.id), [
            "mlx-ask",
            "mlx-community/Nemotron-Labs-Diffusion-3B-4bit",
        ])
        XCTAssertEqual(catalog.model(id: "mlx-ask")?.capability, .chatText)
        XCTAssertEqual(catalog.model(id: "mlx-community/Nemotron-Labs-Diffusion-3B-4bit")?.capability, .diffusionText)
        XCTAssertNil(catalog.model(id: "Qwen/Qwen3-8B"))
    }

    func testModelCatalogPreservesAdvertisedModelsMissingFromMetadataAsChatText() {
        let catalog = ProviderModelCatalog(
            advertisedModelIDs: [
                "mlx-ask",
                "mlx-fast",
            ],
            metadata: [
                ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
            ]
        )

        XCTAssertEqual(catalog.models, [
            ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
            ProviderModelMetadata(id: "mlx-fast", capability: .chatText, state: nil),
        ])
    }

    func testFutureMLXDashboardTextDiffusionShapeBuildsRunnableCatalog() async throws {
        let diffusionModel = "mlx-community/Nemotron-Labs-Diffusion-3B-4bit"
        let transport = FakeTransport(
            responses: [
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-fast"},{"id":"mlx-community/Nemotron-Labs-Diffusion-3B-4bit"}]}"#
                            .utf8
                    )
                ),
                "GET /api/v0/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-plan","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-fast","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-community/Nemotron-Labs-Diffusion-3B-4bit","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"loaded"},{"id":"mlx-community/diffusiongemma-26B-A4B-it-4bit","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"unsupported","unsupported_reason":"Unsupported by installed mlx-lm runtime"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let advertisedModels = try await client.fetchModels().models
        let metadata = try await client.fetchModelMetadata().models
        let catalog = ProviderModelCatalog(advertisedModelIDs: advertisedModels, metadata: metadata)

        XCTAssertEqual(catalog.models.map(\.id), [
            "mlx-ask",
            "mlx-plan",
            "mlx-fast",
            diffusionModel,
        ])
        XCTAssertEqual(catalog.model(id: "mlx-ask")?.capability, .chatText)
        XCTAssertEqual(catalog.model(id: diffusionModel)?.capability, .diffusionText)
        XCTAssertTrue(catalog.canSend(with: "mlx-ask"))
        XCTAssertTrue(catalog.canSend(with: diffusionModel))
        XCTAssertNil(catalog.model(id: "mlx-community/diffusiongemma-26B-A4B-it-4bit"))
        XCTAssertEqual(catalog.defaultSelection(persistedSelection: ""), "mlx-ask")
    }
}

final class LocalProviderURLValidatorTests: XCTestCase {
    func testAcceptsLocalhostProviderURLs() {
        XCTAssertNotNil(LocalProviderURLValidator.providerURL(from: "http://127.0.0.1:8123"))
        XCTAssertNotNil(LocalProviderURLValidator.providerURL(from: "http://localhost:8123"))
        XCTAssertNotNil(LocalProviderURLValidator.providerURL(from: "http://[::1]:8123"))
    }

    func testRejectsRemoteAndUnsupportedProviderURLs() {
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://192.168.1.10:8123"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "https://example.com"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "file:///tmp/provider"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "provider"))
    }
}

final class ProviderLogSanitizerTests: XCTestCase {
    func testBaseURLDescriptionIncludesOnlySchemeHostAndPort() {
        let url = URL(string: "http://user:secret@127.0.0.1:8123/private/path?token=abc")!

        XCTAssertEqual(
            ProviderLogSanitizer.safeBaseURLDescription(url),
            "http://127.0.0.1:8123"
        )
    }

    func testResponseSnippetTruncatesAndNormalisesWhitespace() {
        let data = Data("first line\nsecond line with a lot of extra text".utf8)

        XCTAssertEqual(
            ProviderLogSanitizer.responseSnippet(data, maxLength: 26),
            "first line second line ..."
        )
    }

    func testResponseSnippetReportsBinaryData() {
        let data = Data([0xFF, 0xFE, 0x00])

        XCTAssertEqual(
            ProviderLogSanitizer.responseSnippet(data, maxLength: 24),
            "<non-utf8 body: 3 bytes>"
        )
    }
}

struct MockResponse {
    let statusCode: Int
    let body: Data
}

extension FakeTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        var key = "\(method) \(path)"

        if let body = request.httpBody,
           let decodedBody = String(data: body, encoding: .utf8),
           decodedBody.contains("\"stream\":true") {
            let streamingKey = "\(key) stream=true"
            if responses[streamingKey] != nil {
                key = streamingKey
            }
        }

        guard let response = responses[key] else {
            throw URLError(.badServerResponse)
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response.body, httpResponse)
    }
}

final class RecordingTransport: HTTPTransport {
    private let response: MockResponse
    private(set) var requestMethods: [String] = []
    private(set) var requestPaths: [String] = []
    private(set) var requestBodies: [String] = []

    init(response: MockResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestMethods.append(request.httpMethod ?? "GET")
        requestPaths.append(request.url?.path ?? "")
        requestBodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response.body, httpResponse)
    }
}
