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
                "--base-url", "http://127.0.0.1:9999/v1",
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

    func testBaseURLAllowsOnlyLocalHTTPProviderForms() throws {
        let accepted = [
            "http://127.0.0.1:8123",
            "http://localhost:8123",
            "http://[::1]:8123",
            "http://127.0.0.1:8123/v1",
        ]

        for value in accepted {
            let options = try CLIOptions(arguments: ["--base-url", value])
            XCTAssertEqual(options.baseURL.path, "")
        }
    }

    func testBaseURLRejectsRemoteCredentialsQueriesFragmentsAndUnexpectedPaths() {
        let rejected = [
            "https://127.0.0.1:8123",
            "http://192.168.1.10:8123",
            "http://user:pass@127.0.0.1:8123",
            "http://127.0.0.1:8123?token=abc",
            "http://127.0.0.1:8123#fragment",
            "http://127.0.0.1:8123/provider/v1/models",
        ]

        for value in rejected {
            XCTAssertThrowsError(try CLIOptions(arguments: ["--base-url", value])) { error in
                XCTAssertEqual(error as? CLIOptionsError, .invalidBaseURLError(value))
            }
        }
    }
}

final class FakeTransport: HTTPTransport {
    private let responses: [String: MockResponse]
    private(set) var requestKeys: [String] = []

    init(responses: [String: MockResponse]) {
        self.responses = responses
    }
}

final class SmokeTestRunnerTests: XCTestCase {
    func testSmokeRunnerPassesWithCurrentDashboardNormalChatContract() async throws {
        let transport = SmokeStreamingTransport(
            responses: [
                "GET /health": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"status":"ok"}"#.utf8)
                ),
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-coding"},{"id":"mlx-community/Tiny"}]}"#
                            .utf8
                    )
                ),
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"alias","role":"ask","generation_type":"text","model_family":"chat","state":"loaded","resolved_model":"mlx-community/Tiny","effective_model":"mlx-community/Tiny","routing_state":"role_endpoint","effective_port":8080,"runtime":"mlx-lm","model_type":"gpt_oss","supports_streaming":true,"supported_generation_modes":["chat"],"max_context_length":32768,"max_output_tokens":2048},{"id":"mlx-plan","type":"alias","role":"plan","generation_type":"text","model_family":"chat","state":"loaded","resolved_model":"mlx-community/Planner","effective_model":"mlx-community/Planner","routing_state":"role_endpoint","effective_port":8081},{"id":"mlx-coding","type":"alias","role":"coding","generation_type":"text","model_family":"chat","state":"loaded","resolved_model":"mlx-community/Coder","effective_model":"mlx-community/Tiny","routing_state":"active_model_fallback","effective_port":8080,"fallback_reason":"role server unavailable; using active model"},{"id":"mlx-community/Tiny","type":"llm","generation_type":"text","model_family":"chat","state":"loaded"}]}"#
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
                    body: Data(#"{"id":"resp","object":"responses","output":[{"type":"text","text":"ok"}]}"#.utf8)
                ),
                "POST /provider/v1/mode-advice": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"suggested_mode":"plan","confidence":0.91,"should_suggest_switch":true,"current_mode":"ask","reason":"Planning prompt."}"#.utf8)
                ),
            ],
            streamStatusCode: 200,
            streamChunks: [
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"started","model":"mlx-community/Tiny","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":null,"output_tokens":null,"total_tokens":null}}"#
                    + "\n\n",
                #"data: {"model":"mlx-community/Tiny","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let runner = SmokeTestRunner(client: client)
        let report = await runner.run(includeStreamingCheck: true)

        XCTAssertEqual(report.checks.map(\.name), [
            "Health",
            "Models",
            "Provider metadata",
            "Alias metadata",
            "Routing metadata",
            "Mode advice",
            "Chat completions",
            "Responses",
            "Chat stream",
        ])
        XCTAssertTrue(report.allPassed)
        XCTAssertEqual(transport.streamRequestPaths, ["/v1/chat/completions"])
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
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-coding"}]}"#
                            .utf8
                    )
                ),
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"alias","role":"ask","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-plan","type":"alias","role":"plan","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-coding","type":"alias","role":"coding","generation_type":"text","model_family":"chat","state":"loaded"}]}"#
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
                "POST /provider/v1/mode-advice": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"suggested_mode":"plan","confidence":0.91,"should_suggest_switch":true,"current_mode":"ask","reason":"Planning prompt."}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let runner = SmokeTestRunner(client: client)
        let report = await runner.run(includeStreamingCheck: false)

        XCTAssertFalse(report.checks.contains { $0.name == "Chat stream" })
        XCTAssertTrue(report.allPassed)
        XCTAssertFalse(report.includeStreamingCheck)
    }

    func testSmokeRunnerFailsWhenCanonicalCodingAliasIsMissingEvenIfLegacyFastExists() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /health": MockResponse(statusCode: 200, body: Data(#"{"status":"ok"}"#.utf8)),
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-fast"}]}"#.utf8)
                ),
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"object":"list","data":[{"id":"mlx-ask","role":"ask","state":"loaded"},{"id":"mlx-plan","role":"plan","state":"loaded"},{"id":"mlx-fast","role":"coding","state":"loaded"}]}"#.utf8)
                ),
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)
                ),
                "POST /v1/responses": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"output":[{"type":"text","text":"ok"}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let report = await SmokeTestRunner(client: client).run(includeStreamingCheck: false)
        let modelsCheck = try XCTUnwrap(report.checks.first { $0.name == "Models" })

        XCTAssertFalse(modelsCheck.passed)
        XCTAssertEqual(modelsCheck.details, "missing canonical alias: mlx-coding; legacy mlx-fast is not sufficient")
    }
}

final class URLSessionHTTPTransportTests: XCTestCase {
    func testDefaultTransportDoesNotCapStreamingResourceLifetime() {
        let transport = URLSessionHTTPTransport(timeout: 60)

        XCTAssertEqual(transport.requestTimeout, 60)
        XCTAssertEqual(transport.resourceTimeout, 0)
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

    func testCompleteChatSplitsChannelMarkedThinkingFromFinalAnswer() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","model":"mlx-ask","choices":[{"index":0,"message":{"role":"assistant","content":"<|channel|>analysis<|message|>Need to be brief.<|end|><|start|>assistant<|channel|>final<|message|>**Done**\n\n- one<|end|>"}}]}"#
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

        XCTAssertEqual(result.assistantText, "**Done**\n\n- one")
        XCTAssertEqual(result.reasoning, "Need to be brief.")
        XCTAssertFalse(result.assistantText.contains("<|channel|>"))
        XCTAssertFalse(result.assistantText.contains("<|message|>"))
        XCTAssertFalse(result.assistantText.contains("<|end|>"))
        XCTAssertFalse(result.assistantText.contains("<|start|>"))
    }

    func testCompleteChatPreservesSeparateReasoningField() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","model":"mlx-ask","choices":[{"index":0,"message":{"role":"assistant","content":"Final answer.","reasoning":"Hidden chain."}}]}"#
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

        XCTAssertEqual(result.assistantText, "Final answer.")
        XCTAssertEqual(result.reasoning, "Hidden chain.")
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
            model: "mlx-ask",
            messages: [ChatTranscriptMessage(role: "user", content: "Use fallback")]
        )

        XCTAssertEqual(result.model, "mlx-ask")
        XCTAssertEqual(result.assistantText, "Fallback text reply.")
        XCTAssertEqual(result.statusCode, 200)
    }

    func testCompleteChatSplitsChannelMarkedThinkingFromAnswer() async throws {
        let transport = FakeTransport(
            responses: [
                "POST /v1/chat/completions": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"id":"chat","choices":[{"index":0,"message":{"role":"assistant","content":"<|channel|>analysis<|message|>Need to answer briefly.<|end|><|start|>assistant<|channel|>final<|message|>**Done**\n\n- item<|end|>"}}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.completeChat(
            model: "mlx-ask",
            messages: [ChatTranscriptMessage(role: "user", content: "Summarise")]
        )

        XCTAssertEqual(result.assistantText, "**Done**\n\n- item")
        XCTAssertEqual(result.reasoning, "Need to answer briefly.")
        XCTAssertFalse(result.assistantText.contains("<|channel|>"))
        XCTAssertFalse(result.assistantText.contains("<|message|>"))
        XCTAssertFalse(result.assistantText.contains("<|end|>"))
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

    func testStreamChatSendsStreamingRequestAndEmitsContentDeltas() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"data: {"model":"mlx-community/Tiny","choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"# + "\n\n",
                #"data: {"model":"mlx-community/Tiny","choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
            )
        )

        XCTAssertEqual(deltas, [
            ChatStreamDelta(content: "Hel", finishReason: nil, model: "mlx-community/Tiny"),
            ChatStreamDelta(content: "lo", finishReason: "stop", model: "mlx-community/Tiny"),
        ])
        XCTAssertEqual(transport.requestPaths, ["/v1/chat/completions"])
        XCTAssertTrue(transport.requestBodies.first?.contains(#""stream":true"#) == true)
        XCTAssertTrue(transport.requestBodies.first?.contains(#""stream_options":{"include_usage":true}"#) == true)
    }

    func testStreamChatParsesLengthFinishReasonAndReportedModel() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"data: {"model":"mlx-community/gpt-oss-20b-MXFP4-Q8","choices":[{"delta":{"content":"Partial"},"finish_reason":"length"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
            )
        )

        XCTAssertEqual(deltas, [
            ChatStreamDelta(
                content: "Partial",
                finishReason: "length",
                model: "mlx-community/gpt-oss-20b-MXFP4-Q8"
            ),
        ])
    }

    func testCompleteChatDoesNotSendStreamOptionsForNonStreamingRequest() async throws {
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(#"{"id":"chat","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        _ = try await client.completeChat(
            model: "mlx-ask",
            messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
        )

        XCTAssertFalse(transport.requestBodies.first?.contains("stream_options") == true)
    }

    func testStreamChatParsesMLXUsageEventsWithoutAppendingAssistantText() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"started","model":"mlx-community/Tiny","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":null,"output_tokens":null,"total_tokens":null}}"#
                    + "\n\n",
                #"data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"# + "\n\n",
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"completed","model":"mlx-community/Tiny","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":10,"output_tokens":4,"total_tokens":14}}"#
                    + "\n\n",
                #"data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
            )
        )

        XCTAssertEqual(deltas.map(\.content).joined(), "Hello")
        XCTAssertEqual(deltas, [
            ChatStreamDelta(
                content: "",
                usageState: MLXStreamUsageState(
                    phase: "started",
                    model: "mlx-community/Tiny",
                    context: MLXStreamUsageContext(limitTokens: 32768),
                    tokens: MLXStreamUsageTokens()
                )
            ),
            ChatStreamDelta(content: "Hel"),
            ChatStreamDelta(
                content: "",
                usageState: MLXStreamUsageState(
                    phase: "completed",
                    model: "mlx-community/Tiny",
                    context: MLXStreamUsageContext(limitTokens: 32768),
                    tokens: MLXStreamUsageTokens(inputTokens: 10, outputTokens: 4, totalTokens: 14)
                )
            ),
            ChatStreamDelta(content: "lo", finishReason: "stop"),
        ])
    }

    func testStreamChatParsesProgressiveMLXUsageEventsWithoutAppendingAssistantText() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"started","model":"mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":null,"output_tokens":null,"total_tokens":null,"estimated":false}}"#
                    + "\n\n",
                #"data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"# + "\n\n",
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"streaming","model":"mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":10,"output_tokens":4,"total_tokens":14,"estimated":true}}"#
                    + "\n\n",
                #"data: {"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}"# + "\n\n",
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"completed","model":"mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":10,"output_tokens":5,"total_tokens":15,"estimated":false}}"#
                    + "\n\n",
                #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-plan",
                messages: [ChatTranscriptMessage(role: "user", content: "Plan a Pong SPA")]
            )
        )

        XCTAssertEqual(deltas.map(\.content).joined(), "Hello")
        XCTAssertEqual(deltas.compactMap(\.usageState).map(\.phase), ["started", "streaming", "completed"])
        XCTAssertEqual(deltas.compactMap(\.usageState).map(\.model), [
            "mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit",
            "mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit",
            "mlx-plan -> mlx-community/Qwen3.6-35B-A3B-4bit",
        ])
        XCTAssertEqual(deltas.compactMap(\.usageState)[1].tokens.totalTokens, 14)
        XCTAssertEqual(deltas.compactMap(\.usageState)[1].tokens.estimated, true)
        XCTAssertEqual(deltas.compactMap(\.usageState)[2].tokens.totalTokens, 15)
        XCTAssertEqual(deltas.compactMap(\.usageState)[2].tokens.estimated, false)
    }

    func testStreamChatUsageEventsPreserveNullValuesAsUnknown() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"event: mlx.usage"# + "\n"
                    + #"data: {"type":"mlx.usage","phase":"started","model":"mlx-community/Tiny","context":{"limit_tokens":32768,"used_tokens":null,"remaining_tokens":null,"usage_ratio":null},"tokens":{"input_tokens":null,"output_tokens":null,"total_tokens":null}}"#
                    + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "hello")]
            )
        )

        let usageState = try XCTUnwrap(deltas.first?.usageState)
        XCTAssertEqual(usageState.context.limitTokens, 32768)
        XCTAssertNil(usageState.context.usedTokens)
        XCTAssertNil(usageState.context.remainingTokens)
        XCTAssertNil(usageState.context.usageRatio)
        XCTAssertNil(usageState.tokens.inputTokens)
        XCTAssertNil(usageState.tokens.outputTokens)
        XCTAssertNil(usageState.tokens.totalTokens)
    }

    func testStreamChatIgnoresUnknownNamedEvents() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"event: mlx.debug"# + "\n" + #"data: {"message":"ignored"}"# + "\n\n",
                #"data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "hello")]
            )
        )

        XCTAssertEqual(deltas, [
            ChatStreamDelta(content: "ok", finishReason: "stop"),
        ])
    }

    func testStreamChatSplitsChannelMarkedDelta() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"data: {"choices":[{"delta":{"content":"<|channel|>analysis<|message|>Think first.<|end|><|channel|>final<|message|>Final text.<|end|>"}}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "Say hello")]
            )
        )

        XCTAssertEqual(deltas, [
            ChatStreamDelta(content: "Final text.", reasoning: "Think first."),
        ])
    }

    func testStreamChatHandlesSplitFramesAndKeepAliveLines() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                "\n",
                #"data: {"choices":[{"delta":{"content":"He"},"finish_reason":null}]}"#,
                "\n\n",
                #"data: {"choices":[{"delta":{"content":"y"},"finish_reason":null}]}"# + "\n\n" + "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "Say hey")]
            )
        )

        XCTAssertEqual(deltas.map(\.content), ["He", "y"])
    }

    func testStreamChatSplitsChannelMarkedThinkingFromAnswer() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: [
                #"data: {"choices":[{"delta":{"content":"<|channel|>analysis<|message|>Work privately.<|end|><|channel|>final<|message|>Visible answer<|end|>"},"finish_reason":"stop"}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let deltas = try await collectStream(
            client.streamChat(
                model: "mlx-ask",
                messages: [ChatTranscriptMessage(role: "user", content: "hello")]
            )
        )

        XCTAssertEqual(deltas, [
            ChatStreamDelta(content: "Visible answer", finishReason: "stop", reasoning: "Work privately."),
        ])
    }

    func testStreamChatThrowsForNonSuccessStatus() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 503,
            chunks: [#"{"error":"provider unavailable"}"#]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        do {
            _ = try await collectStream(
                client.streamChat(
                    model: "mlx-ask",
                    messages: [ChatTranscriptMessage(role: "user", content: "hello")]
                )
            )
            XCTFail("Expected stream to throw for non-success response.")
        } catch let error as ProviderClientError {
            XCTAssertEqual(error.localizedDescription, #"Unexpected status code 503: {"error":"provider unavailable"}"#)
        }
    }

    func testStreamChatThrowsForMalformedJSONFrame() async throws {
        let transport = StreamingRecordingTransport(
            statusCode: 200,
            chunks: ["data: {not-json}\n\n"]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        do {
            _ = try await collectStream(
                client.streamChat(
                    model: "mlx-ask",
                    messages: [ChatTranscriptMessage(role: "user", content: "hello")]
                )
            )
            XCTFail("Expected stream to throw for malformed JSON.")
        } catch let error as ProviderClientError {
            XCTAssertTrue(error.localizedDescription.contains("Malformed stream frame"))
        }
    }

    private func collectStream(_ stream: AsyncThrowingStream<ChatStreamDelta, Error>) async throws -> [ChatStreamDelta] {
        var deltas: [ChatStreamDelta] = []
        for try await delta in stream {
            deltas.append(delta)
        }
        return deltas
    }
}

final class ChatMessagePresentationTests: XCTestCase {
    func testAssistantContentRendersMarkdownMarkers() throws {
        let rendered = try ChatMessagePresentation.renderedContent(
            role: "assistant",
            content: "**Bold** response"
        )

        XCTAssertEqual(String(rendered.characters), "Bold response")
    }

    func testUserContentKeepsMarkdownMarkersLiteral() throws {
        let rendered = try ChatMessagePresentation.renderedContent(
            role: "user",
            content: "**Literal** prompt"
        )

        XCTAssertEqual(String(rendered.characters), "**Literal** prompt")
    }

    func testAssistantContentParsesMarkdownBlocksForRendering() throws {
        let blocks = ChatMessagePresentation.contentBlocks(
            role: "assistant",
            content: """
            Below is a **review** of the script.

            Feel free to cherry-pick the changes.

            1. What the script already does
            2. Things that could be improved

            ### Command-line usage

            ```bash
            python towers_of_hanoi.py 3
            ```
            """
        )

        XCTAssertEqual(blocks, [
            ChatContentBlock(kind: .paragraph, text: "Below is a **review** of the script."),
            ChatContentBlock(kind: .paragraph, text: "Feel free to cherry-pick the changes."),
            ChatContentBlock(kind: .numberedListItem, text: "What the script already does", ordinal: 1),
            ChatContentBlock(kind: .numberedListItem, text: "Things that could be improved", ordinal: 2),
            ChatContentBlock(kind: .heading, text: "Command-line usage", level: 3),
            ChatContentBlock(kind: .code, text: "python towers_of_hanoi.py 3", language: "bash"),
        ])
    }

    func testAssistantFencedCodeKeepsMarkdownLikeCharactersLiteral() throws {
        let blocks = ChatMessagePresentation.contentBlocks(
            role: "assistant",
            content: """
            ```python
            if __name__ == "__main__":
                print(f"Move {i}: {src} -> {dst}")
            ```
            """
        )

        XCTAssertEqual(blocks, [
            ChatContentBlock(
                kind: .code,
                text: """
                if __name__ == "__main__":
                    print(f"Move {i}: {src} -> {dst}")
                """,
                language: "python"
            ),
        ])
    }

    func testAssistantContentParsesPipeTablesForRendering() {
        let blocks = ChatMessagePresentation.contentBlocks(
            role: "assistant",
            content: """
            | Phase | Goal | Time |
            | --- | --- | ---: |
            | Setup | Create repo | 5 min |
            | Polish | Manual tests | 20 min |
            """
        )

        XCTAssertEqual(blocks, [
            ChatContentBlock(
                kind: .table,
                text: "",
                tableRows: [
                    ["Phase", "Goal", "Time"],
                    ["Setup", "Create repo", "5 min"],
                    ["Polish", "Manual tests", "20 min"],
                ]
            ),
        ])
    }

    func testAssistantChannelMarkedContentSplitsReasoningAndAnswer() {
        let result = ChatMessagePresentation.normalizedAssistantContent(
            content: "<|channel|>analysis<|message|>Draft internally.<|end|><|channel|>final<|message|>Final **answer**.<|end|>"
        )

        XCTAssertEqual(result.content, "Final **answer**.")
        XCTAssertEqual(result.reasoning, "Draft internally.")
    }

    func testAssistantChannelMarkedContentWithoutMessageMarkersDoesNotLeakChannelNames() {
        let result = ChatMessagePresentation.normalizedAssistantContent(
            content: "<|channel|>analysisWe need to plan privately.<|end|><|start|>assistant<|channel|>final### Final answer<|end|>"
        )

        XCTAssertEqual(result.content, "### Final answer")
        XCTAssertEqual(result.reasoning, "We need to plan privately.")
        XCTAssertFalse(result.content.contains("analysis"))
        XCTAssertFalse(result.content.contains("assistantfinal"))
    }

    func testAssistantBareCompactChannelTextDoesNotLeakAnalysisIntoVisibleAnswer() {
        let result = ChatMessagePresentation.normalizedAssistantContent(
            content: "analysisWe need to answer privately.assistantfinalBelow is the answer."
        )

        XCTAssertEqual(result.content, "Below is the answer.")
        XCTAssertEqual(result.reasoning, "We need to answer privately.")
        XCTAssertFalse(result.content.contains("analysis"))
        XCTAssertFalse(result.content.contains("assistantfinal"))
    }

    func testAssistantReasoningRepairsSavedTokenFragmentParagraphs() {
        let result = ChatMessagePresentation.normalizedAssistantContent(
            content: "Final answer.",
            reasoning: "Here\n\n's\n\n a\n\n thinking\n\n process\n\n:\n\n1\n\n.\n\n  **\n\nUnder\n\nstand\n\n User\n\n Request\n\n:**\n\n -\n\n **\n\nGoal\n\n:**\n\n Create\n\n a\n\n P\n\nong\n\n game"
        )

        XCTAssertEqual(result.content, "Final answer.")
        XCTAssertEqual(
            result.reasoning,
            """
            Here's a thinking process:
            1. **Understand User Request:**
            - **Goal:** Create a Pong game
            """
        )
    }

    func testAssistantReasoningAppendPreservesStreamingTokenSpacing() {
        var combined = ChatMessagePresentation.appendingReasoning("Here", delta: "'s")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "a")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "thinking")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "process")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: ":")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "1")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: ".")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "**")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "Under")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "stand")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "User")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: "Request")
        combined = ChatMessagePresentation.appendingReasoning(combined, delta: ":**")

        XCTAssertEqual(
            combined,
            """
            Here's a thinking process:
            1. **Understand User Request:**
            """
        )
    }

    func testAssistantContentBlocksNormaliseChannelMarkedSavedContent() {
        let blocks = ChatMessagePresentation.contentBlocks(
            role: "assistant",
            content: "<|channel|>analysis<|message|>Draft internally.<|end|><|channel|>final<|message|>### Final\n\n- answer<|end|>"
        )

        XCTAssertEqual(blocks, [
            ChatContentBlock(kind: .heading, text: "Final", level: 3),
            ChatContentBlock(kind: .bulletListItem, text: "answer"),
        ])
    }
}

final class TranscriptAutoScrollPolicyTests: XCTestCase {
    func testScrollsForNewMessagesButNotStreamingRevisions() {
        XCTAssertTrue(TranscriptAutoScrollPolicy.shouldScrollToLatest(for: .messageCountChanged))
        XCTAssertFalse(TranscriptAutoScrollPolicy.shouldScrollToLatest(for: .transcriptRevisionChanged))
    }
}

final class ConversationStoreTests: XCTestCase {
    func testLoadLegacySummaryWithSelectedModelStillDecodes() throws {
        let summaryID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let data = Data(
            """
            [
              {
                "id": "\(summaryID.uuidString)",
                "title": "Legacy chat",
                "updatedAt": 1000,
                "selectedModel": "mlx-plan"
              }
            ]
            """.utf8
        )

        let summaries = try JSONDecoder().decode([ConversationSummary].self, from: data)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.id, summaryID)
        XCTAssertEqual(summaries.first?.title, "Legacy chat")
        XCTAssertEqual(summaries.first?.selectedModel, "mlx-plan")
    }

    func testCreateConversationWritesIndexAndConversationFile() throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(applicationSupportDirectory: root)

        let conversation = try store.createConversation(
            providerBaseURL: "http://127.0.0.1:8123",
            selectedModel: "mlx-ask",
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(conversation.title, "New Chat")
        XCTAssertEqual(conversation.providerBaseURL, "http://127.0.0.1:8123")
        XCTAssertEqual(conversation.selectedModel, "mlx-ask")
        XCTAssertEqual(conversation.messages, [])

        let conversationsDirectory = root
            .appending(path: "Conversations", directoryHint: .isDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationsDirectory.appending(path: "index.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversationsDirectory.appending(path: "\(conversation.id.uuidString).json").path))

        let summaries = try store.loadSummaries()
        XCTAssertEqual(summaries, [
            ConversationSummary(
                id: conversation.id,
                title: "New Chat",
                updatedAt: Date(timeIntervalSince1970: 1_000),
                selectedModel: "mlx-ask"
            )
        ])
    }

    func testLoadSummariesSortsByUpdatedAtDescending() throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(applicationSupportDirectory: root)

        let older = try store.createConversation(
            providerBaseURL: "http://127.0.0.1:8123",
            selectedModel: "mlx-plan",
            now: Date(timeIntervalSince1970: 1_000)
        )
        let newer = try store.createConversation(
            providerBaseURL: "http://127.0.0.1:8123",
            selectedModel: "mlx-coding",
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(try store.loadSummaries().map(\.id), [newer.id, older.id])
    }

    func testSaveLoadPreservesConversationAndNormalisesStreamingFlags() throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(applicationSupportDirectory: root)
        var conversation = try store.createConversation(
            providerBaseURL: "http://127.0.0.1:8123",
            selectedModel: "mlx-ask",
            now: Date(timeIntervalSince1970: 1_000)
        )
        conversation.messages = [
            ChatDisplayMessage(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                role: "user",
                content: "Please review this code",
                createdAt: Date(timeIntervalSince1970: 1_010)
            ),
            ChatDisplayMessage(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                role: "assistant",
                content: "Partial answer",
                createdAt: Date(timeIntervalSince1970: 1_011),
                isStreaming: true,
                didFail: true
            ),
        ]

        try store.save(conversation, now: Date(timeIntervalSince1970: 1_020))

        let loaded = try store.loadConversation(id: conversation.id)
        XCTAssertEqual(loaded.title, "Please review this code")
        XCTAssertEqual(loaded.updatedAt, Date(timeIntervalSince1970: 1_020))
        XCTAssertEqual(loaded.providerBaseURL, "http://127.0.0.1:8123")
        XCTAssertEqual(loaded.selectedModel, "mlx-ask")
        XCTAssertEqual(loaded.messages.count, 2)
        XCTAssertEqual(loaded.messages[0].content, "Please review this code")
        XCTAssertEqual(loaded.messages[1].content, "Partial answer")
        XCTAssertFalse(loaded.messages[1].isStreaming)
        XCTAssertTrue(loaded.messages[1].didFail)
    }

    func testChatDisplayMessagePreservesResponseMetadataAndDecodesLegacyMessages() throws {
        let usageState = MLXStreamUsageState(
            phase: "completed",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(
                limitTokens: 32768,
                usedTokens: nil,
                remainingTokens: nil,
                usageRatio: nil
            ),
            tokens: MLXStreamUsageTokens(inputTokens: 10, outputTokens: 4, totalTokens: 14)
        )
        let message = ChatDisplayMessage(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            role: "assistant",
            content: "Done",
            requestedModel: "mlx-ask",
            responseModel: "mlx-community/Tiny",
            finishReason: "length",
            usageState: usageState
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatDisplayMessage.self, from: data)
        XCTAssertEqual(decoded.requestedModel, "mlx-ask")
        XCTAssertEqual(decoded.responseModel, "mlx-community/Tiny")
        XCTAssertEqual(decoded.finishReason, "length")
        XCTAssertEqual(decoded.usageState, usageState)

        let legacyData = Data(
            """
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "role": "assistant",
              "content": "Legacy",
              "createdAt": 1000,
              "isStreaming": false,
              "didFail": false
            }
            """.utf8
        )
        let legacy = try JSONDecoder().decode(ChatDisplayMessage.self, from: legacyData)
        XCTAssertNil(legacy.requestedModel)
        XCTAssertNil(legacy.responseModel)
        XCTAssertNil(legacy.finishReason)
        XCTAssertNil(legacy.usageState)
    }

    func testUsageStateIsDisplayableWhenItHasDataOrProviderPhase() {
        XCTAssertTrue(
            MLXStreamUsageState(
                phase: "completed",
                model: "mlx-community/Tiny",
                context: MLXStreamUsageContext(),
                tokens: MLXStreamUsageTokens()
            ).hasDisplayableUsageData
        )

        XCTAssertTrue(
            MLXStreamUsageState(
                phase: "started",
                model: "mlx-community/Tiny",
                context: MLXStreamUsageContext(),
                tokens: MLXStreamUsageTokens()
            ).hasDisplayableUsageData
        )

        XCTAssertTrue(
            MLXStreamUsageState(
                phase: "started",
                model: "mlx-community/Tiny",
                context: MLXStreamUsageContext(limitTokens: 32768),
                tokens: MLXStreamUsageTokens()
            ).hasDisplayableUsageData
        )

        XCTAssertTrue(
            MLXStreamUsageState(
                phase: "completed",
                model: "mlx-community/Tiny",
                context: MLXStreamUsageContext(),
                tokens: MLXStreamUsageTokens(inputTokens: 10, outputTokens: 4, totalTokens: 14)
            ).hasDisplayableUsageData
        )
    }

    func testUsageStateDisplayLinesShowProgressiveContextAndTokenCounts() {
        let usageState = MLXStreamUsageState(
            phase: "started",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(
                limitTokens: 32768,
                usedTokens: 1536,
                remainingTokens: 31232,
                usageRatio: 0.046875
            ),
            tokens: MLXStreamUsageTokens(
                inputTokens: 120,
                outputTokens: 45,
                totalTokens: 165
            )
        )

        XCTAssertEqual(
            usageState.displayLines,
            [
                "Usage: streaming",
                "Context: 1,536 / 32,768 used (4.7%) - 31,232 remaining",
                "Tokens: 165 total / 120 in / 45 out",
            ]
        )
    }

    func testUsageStateDisplayLinesLabelEstimatedStreamingTotals() {
        let usageState = MLXStreamUsageState(
            phase: "streaming",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(limitTokens: 32768),
            tokens: MLXStreamUsageTokens(
                inputTokens: 120,
                outputTokens: 45,
                totalTokens: 165,
                estimated: true
            )
        )

        XCTAssertEqual(
            usageState.displayLines,
            [
                "Usage: streaming",
                "Context: 32,768 limit",
                "Tokens: ~165 total / 120 in / 45 out",
            ]
        )
    }

    func testUsageStateDisplayLinesFallsBackToComputedTotalWhenMissing() {
        let usageState = MLXStreamUsageState(
            phase: "completed",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(),
            tokens: MLXStreamUsageTokens(inputTokens: 120, outputTokens: 45)
        )

        XCTAssertEqual(
            usageState.displayLines,
            [
                "Usage: completed",
                "Tokens: 165 total / 120 in / 45 out",
            ]
        )
    }

    func testUsageStateDisplayLinesShowPartialProgressiveTokenCounts() {
        let usageState = MLXStreamUsageState(
            phase: "started",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(limitTokens: 32768),
            tokens: MLXStreamUsageTokens(outputTokens: 45)
        )

        XCTAssertEqual(
            usageState.displayLines,
            [
                "Usage: streaming",
                "Context: 32,768 limit",
                "Tokens: 45 out",
            ]
        )
    }

    func testUsageStateDisplayLinesShowCompletedFallbackWhenNoUsageReported() {
        let usageState = MLXStreamUsageState(
            phase: "completed",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(),
            tokens: MLXStreamUsageTokens()
        )

        XCTAssertEqual(usageState.displayLines, ["Usage: not reported by provider"])
    }

    func testLatestHeaderUsageStateUsesLatestAssistantUsageWithUsableDisplayLines() {
        let olderUsage = MLXStreamUsageState(
            phase: "completed",
            model: "mlx-ask -> mlx-community/Small",
            context: MLXStreamUsageContext(),
            tokens: MLXStreamUsageTokens(inputTokens: 10, outputTokens: 4, totalTokens: 14)
        )
        let latestUsage = MLXStreamUsageState(
            phase: "streaming",
            model: "mlx-plan -> mlx-community/Large",
            context: MLXStreamUsageContext(limitTokens: 32768),
            tokens: MLXStreamUsageTokens(outputTokens: 45, estimated: true)
        )

        let messages = [
            ChatDisplayMessage(role: "assistant", content: "older", usageState: olderUsage),
            ChatDisplayMessage(role: "user", content: "newer user", usageState: latestUsage),
            ChatDisplayMessage(role: "assistant", content: "latest", usageState: latestUsage),
        ]

        XCTAssertEqual(ChatUsagePresentation.latestHeaderUsageState(in: messages), latestUsage)
    }

    func testLatestHeaderUsageStateSkipsUnknownCompletedUsage() {
        let unknownUsage = MLXStreamUsageState(
            phase: "completed",
            model: "mlx-community/Tiny",
            context: MLXStreamUsageContext(),
            tokens: MLXStreamUsageTokens()
        )

        XCTAssertNil(
            ChatUsagePresentation.latestHeaderUsageState(
                in: [ChatDisplayMessage(role: "assistant", content: "", usageState: unknownUsage)]
            )
        )
    }

    func testDeleteConversationRemovesFileAndIndexEntry() throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(applicationSupportDirectory: root)
        let conversation = try store.createConversation(
            providerBaseURL: "http://127.0.0.1:8123",
            selectedModel: "mlx-ask",
            now: Date(timeIntervalSince1970: 1_000)
        )

        try store.deleteConversation(id: conversation.id)

        XCTAssertEqual(try store.loadSummaries(), [])
        let conversationURL = root
            .appending(path: "Conversations", directoryHint: .isDirectory)
            .appending(path: "\(conversation.id.uuidString).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversationURL.path))
    }

    private func temporaryStoreRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ConversationStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

final class ProviderModeAdviceTests: XCTestCase {
    func testModeAdviceInputIncludesSystemDeveloperAndUserTextOnly() {
        let input = ModeAdviceCoordinator.modeAdviceInput(
            from: [
                ChatTranscriptMessage(role: "system", content: "Use local provider routing."),
                ChatTranscriptMessage(role: "developer", content: "You are in PLANNING mode."),
                ChatTranscriptMessage(role: "assistant", content: "Earlier assistant answer."),
                ChatTranscriptMessage(role: "tool", content: "Tool output."),
                ChatTranscriptMessage(role: "user", content: "Map the repository first."),
            ],
            latestPrompt: "Plan the implementation."
        )

        XCTAssertEqual(
            input,
            """
            system: Use local provider routing.

            developer: You are in PLANNING mode.

            user: Map the repository first.

            user: Plan the implementation.
            """
        )
        XCTAssertFalse(input.contains("Earlier assistant answer."))
        XCTAssertFalse(input.contains("Tool output."))
    }

    func testModeAdviceInputFallsBackToLatestPromptWhenTranscriptHasNoRelevantText() {
        let input = ModeAdviceCoordinator.modeAdviceInput(
            from: [
                ChatTranscriptMessage(role: "assistant", content: "Earlier assistant answer."),
                ChatTranscriptMessage(role: "tool", content: "Tool output."),
            ],
            latestPrompt: "Plan the implementation."
        )

        XCTAssertEqual(input, "Plan the implementation.")
    }

    func testFetchModeAdviceSendsLatestPromptAndSelectedModel() async throws {
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(
                    #"{"suggested_mode":"plan","confidence":0.86,"should_suggest_switch":true,"current_mode":"ask","reason":"The prompt asks for implementation planning."}"#
                        .utf8
                )
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let advice = try await client.fetchModeAdvice(
            input: "help me plan this feature",
            selectedModel: "mlx-ask"
        )

        XCTAssertEqual(advice.suggestedMode, "plan")
        XCTAssertEqual(advice.confidence, 0.86)
        XCTAssertEqual(advice.shouldSuggestSwitch, true)
        XCTAssertEqual(advice.currentMode, "ask")
        XCTAssertEqual(advice.reason, "The prompt asks for implementation planning.")
        XCTAssertEqual(transport.requestPaths, ["/provider/v1/mode-advice"])
        XCTAssertEqual(transport.requestBodies.count, 1)
        XCTAssertTrue(transport.requestBodies[0].contains(#""input":"help me plan this feature""#))
        XCTAssertTrue(transport.requestBodies[0].contains(#""selected_model":"mlx-ask""#))
        XCTAssertFalse(transport.requestBodies[0].contains("older transcript text"))
    }

    func testModeAdviceIsRequestedBeforeChatAndAcceptedPlanAliasIsSent() async throws {
        let transport = SequencedRecordingTransport(
            responses: [
                MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"suggested_mode":"plan","confidence":0.86,"should_suggest_switch":true,"current_mode":"ask","reason":"The prompt asks for implementation planning."}"#
                            .utf8
                    )
                ),
                MockResponse(
                    statusCode: 200,
                    body: Data(#"{"id":"chat","model":"mlx-plan","choices":[{"index":0,"message":{"role":"assistant","content":"planned"}}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let catalog = mlxModeAdviceCatalog()

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "help me plan this feature",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { input, selectedModel in
                try await client.fetchModeAdvice(input: input, selectedModel: selectedModel)
            },
            userDecision: { _ in true }
        )
        _ = try await client.completeChat(
            model: modelID,
            messages: [
                ChatTranscriptMessage(role: "user", content: "older transcript text"),
                ChatTranscriptMessage(role: "user", content: "help me plan this feature"),
            ]
        )

        XCTAssertEqual(transport.requestPaths, ["/provider/v1/mode-advice", "/v1/chat/completions"])
        XCTAssertTrue(transport.requestBodies[0].contains(#""input":"help me plan this feature""#))
        XCTAssertFalse(transport.requestBodies[0].contains("older transcript text"))
        XCTAssertTrue(transport.requestBodies[1].contains(#""model":"mlx-plan""#))
        XCTAssertFalse(transport.requestBodies[1].contains("mlx-community"))
    }

    func testPlanningModePromptKeepsAliasAndSendsPromptContextForAdvice() async throws {
        let transport = SequencedRecordingTransport(
            responses: [
                MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"suggested_mode":"plan","confidence":0.92,"should_suggest_switch":true,"current_mode":"coding","reason":"Planning mode prompt."}"#
                            .utf8
                    )
                ),
                MockResponse(
                    statusCode: 200,
                    body: Data(#"{"id":"chat","model":"mlx-plan","choices":[{"index":0,"message":{"role":"assistant","content":"planned"}}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(
                    id: "mlx-coding",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Coder",
                    role: "coding",
                    compatibilityType: "mlx",
                    effectiveModel: "mlx-community/Active"
                ),
                ProviderModelMetadata(
                    id: "mlx-plan",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Planner",
                    role: "plan",
                    compatibilityType: "mlx",
                    effectiveModel: "mlx-community/Planner"
                ),
            ]
        )
        let messages = [
            ChatTranscriptMessage(role: "developer", content: "You are in plan mode. Think first."),
            ChatTranscriptMessage(role: "user", content: "Map the repository."),
        ]
        let adviceInput = ModeAdviceCoordinator.modeAdviceInput(
            from: messages,
            latestPrompt: "Propose the implementation sequence."
        )

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-coding",
            latestPrompt: adviceInput,
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { input, selectedModel in
                try await client.fetchModeAdvice(input: input, selectedModel: selectedModel)
            },
            userDecision: { _ in true }
        )
        _ = try await client.completeChat(
            model: modelID,
            messages: messages + [
                ChatTranscriptMessage(role: "user", content: "Propose the implementation sequence.")
            ]
        )

        XCTAssertEqual(transport.requestPaths, ["/provider/v1/mode-advice", "/v1/chat/completions"])
        XCTAssertTrue(transport.requestBodies[0].contains("developer: You are in plan mode. Think first."))
        XCTAssertTrue(transport.requestBodies[0].contains("user: Map the repository."))
        XCTAssertTrue(transport.requestBodies[0].contains("user: Propose the implementation sequence."))
        XCTAssertTrue(transport.requestBodies[0].contains(#""selected_model":"mlx-coding""#))
        XCTAssertTrue(transport.requestBodies[1].contains(#""model":"mlx-plan""#))
        XCTAssertFalse(transport.requestBodies[1].contains("mlx-community/Coder"))
        XCTAssertFalse(transport.requestBodies[1].contains("mlx-community/Active"))
    }

    func testAutomaticModeAdviceUsesSuggestedAliasWithoutPrompting() async throws {
        let catalog = mlxModeAdviceCatalog()

        let modelID = await ModeAdviceCoordinator.resolveAutomaticAliasForSend(
            baselineAlias: "mlx-ask",
            latestPrompt: "implement this feature",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { selectedPrompt, selectedModel in
                XCTAssertEqual(selectedPrompt, "implement this feature")
                XCTAssertEqual(selectedModel, "mlx-ask")
                return ProviderModeAdvice(
                    suggestedMode: "coding",
                    confidence: 0.91,
                    shouldSuggestSwitch: true,
                    currentMode: "ask",
                    reason: "Coding request."
                )
            }
        )

        XCTAssertEqual(modelID, "mlx-coding")
    }

    func testAutomaticModeAdviceFallsBackToBaselineForUnknownAdvice() async throws {
        let catalog = mlxModeAdviceCatalog()

        let modelID = await ModeAdviceCoordinator.resolveAutomaticAliasForSend(
            baselineAlias: "mlx-ask",
            latestPrompt: "hello",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                ProviderModeAdvice(
                    suggestedMode: "unknown",
                    confidence: 0.2,
                    shouldSuggestSwitch: false,
                    currentMode: "ask",
                    reason: "No clear mode."
                )
            }
        )

        XCTAssertEqual(modelID, "mlx-ask")
    }

    func testAutomaticModeAdviceFallsBackToBaselineWhenAdviceFails() async throws {
        let catalog = mlxModeAdviceCatalog()

        let modelID = await ModeAdviceCoordinator.resolveAutomaticAliasForSend(
            baselineAlias: "mlx-ask",
            latestPrompt: "plan this",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in throw URLError(.timedOut) }
        )

        XCTAssertEqual(modelID, "mlx-ask")
    }

    func testHeuristicFallbackRoutesCreationHowToPromptsToPlanAlias() {
        let modelID = ModeAdviceCoordinator.heuristicAliasForPrompt(
            "how can I create a pong game as a SPA using only HTML/CSS/JS?",
            baselineAlias: "mlx-ask",
            catalog: mlxModeAdviceCatalog()
        )

        XCTAssertEqual(modelID, "mlx-plan")
    }

    func testHeuristicFallbackKeepsBaselineForConcreteModelSelection() {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(id: "mlx-plan", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(id: "mlx-community/Explicit", capability: .chatText, state: "loaded"),
            ]
        )

        let modelID = ModeAdviceCoordinator.heuristicAliasForPrompt(
            "how can I create a pong game?",
            baselineAlias: "mlx-community/Explicit",
            catalog: catalog
        )

        XCTAssertEqual(modelID, "mlx-community/Explicit")
    }

    func testAvailableModeChoicesIncludeOnlySendableCanonicalAliases() {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(id: "mlx-plan", capability: .chatText, state: "loaded"),
                ProviderModelMetadata(id: "mlx-coding", capability: .unsupported(reason: "missing"), state: "unsupported"),
                ProviderModelMetadata(id: "mlx-community/Explicit", capability: .chatText, state: "loaded"),
            ]
        )

        XCTAssertEqual(
            ModeAdviceCoordinator.availableModeChoiceAliases(in: catalog),
            ["mlx-ask", "mlx-plan"]
        )
    }

    func testExplicitCodingChoiceAnnotationIsAvailableForThreeWayPicker() {
        let annotation = ModeAdviceCoordinator.modeSelectionAnnotation(for: "mlx-coding")

        XCTAssertEqual(annotation?.role, "system")
        XCTAssertTrue(annotation?.content.contains("Mode: coding") == true)
        XCTAssertTrue(annotation?.content.contains("coding mode") == true)
    }

    func testExplicitPlanChoiceAnnotatesProviderTranscriptWithoutChangingUserPrompt() async throws {
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(#"{"id":"chat","model":"mlx-plan","choices":[{"index":0,"message":{"role":"assistant","content":"plan"}}]}"#.utf8)
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let messages = ModeAdviceCoordinator.annotatedTranscript(
            [ChatTranscriptMessage(role: "user", content: "How can I create a Pong SPA?")],
            explicitModeAlias: "mlx-plan"
        )

        _ = try await client.completeChat(model: "mlx-plan", messages: messages)

        XCTAssertEqual(transport.requestBodies.count, 1)
        XCTAssertTrue(transport.requestBodies[0].contains(#""role":"system""#))
        XCTAssertTrue(transport.requestBodies[0].contains("Mode: plan"))
        XCTAssertTrue(transport.requestBodies[0].contains("planning mode"))
        XCTAssertTrue(transport.requestBodies[0].contains(#""role":"user""#))
        XCTAssertTrue(transport.requestBodies[0].contains(#""content":"How can I create a Pong SPA?""#))
    }

    func testExplicitAskChoiceAnnotatesProviderTranscriptWithoutChangingUserPrompt() async throws {
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(#"{"id":"chat","model":"mlx-ask","choices":[{"index":0,"message":{"role":"assistant","content":"answer"}}]}"#.utf8)
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)
        let messages = ModeAdviceCoordinator.annotatedTranscript(
            [ChatTranscriptMessage(role: "user", content: "How can I create a Pong SPA?")],
            explicitModeAlias: "mlx-ask"
        )

        _ = try await client.completeChat(model: "mlx-ask", messages: messages)

        XCTAssertEqual(transport.requestBodies.count, 1)
        XCTAssertTrue(transport.requestBodies[0].contains(#""role":"system""#))
        XCTAssertTrue(transport.requestBodies[0].contains("Mode: ask"))
        XCTAssertTrue(transport.requestBodies[0].contains("ask mode"))
        XCTAssertTrue(transport.requestBodies[0].contains(#""role":"user""#))
        XCTAssertTrue(transport.requestBodies[0].contains(#""content":"How can I create a Pong SPA?""#))
    }

    func testHighConfidencePlanAdviceBuildsSwitchPromptAndAcceptingUsesPlanAlias() async throws {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(
                    id: "mlx-ask",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Ask",
                    role: "ask",
                    compatibilityType: "mlx"
                ),
                ProviderModelMetadata(id: "mlx-plan", capability: .chatText, state: "loaded", role: "plan"),
            ]
        )
        var prompts: [ModeAdviceSwitchPrompt] = []

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "help me plan this feature",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                ProviderModeAdvice(
                    suggestedMode: "plan",
                    confidence: 0.86,
                    shouldSuggestSwitch: true,
                    currentMode: "ask",
                    reason: "The prompt asks for implementation planning."
                )
            },
            userDecision: { prompt in
                prompts.append(prompt)
                return true
            }
        )

        XCTAssertEqual(modelID, "mlx-plan")
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.currentModel, "mlx-ask")
        XCTAssertEqual(prompts.first?.suggestedMode, "plan")
        XCTAssertEqual(prompts.first?.suggestedModel, "mlx-plan")
        XCTAssertEqual(prompts.first?.confidencePercent, 86)
        XCTAssertEqual(prompts.first?.reason, "The prompt asks for implementation planning.")
    }

    func testDecliningModeAdviceUsesOriginalAlias() async throws {
        let catalog = mlxModeAdviceCatalog()

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "help me plan this feature",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                ProviderModeAdvice(
                    suggestedMode: "plan",
                    confidence: 0.9,
                    shouldSuggestSwitch: true,
                    currentMode: "ask",
                    reason: "Planning request."
                )
            },
            userDecision: { _ in false }
        )

        XCTAssertEqual(modelID, "mlx-ask")
    }

    func testUnknownAdviceUsesOriginalAliasWithoutPrompting() async throws {
        let catalog = mlxModeAdviceCatalog()
        var didPrompt = false

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "hello",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                ProviderModeAdvice(
                    suggestedMode: "unknown",
                    confidence: 0.2,
                    shouldSuggestSwitch: true,
                    currentMode: "ask",
                    reason: "No clear mode."
                )
            },
            userDecision: { _ in
                didPrompt = true
                return true
            }
        )

        XCTAssertEqual(modelID, "mlx-ask")
        XCTAssertFalse(didPrompt)
    }

    func testFailedAdviceUsesOriginalAliasWithoutPrompting() async throws {
        let catalog = mlxModeAdviceCatalog()
        var didPrompt = false

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "help me plan",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in throw URLError(.timedOut) },
            userDecision: { _ in
                didPrompt = true
                return true
            }
        )

        XCTAssertEqual(modelID, "mlx-ask")
        XCTAssertFalse(didPrompt)
    }

    func testGenericOpenAIProvidersDoNotRequestModeAdvice() async throws {
        let catalog = ProviderModelCatalog(
            models: [ProviderModelMetadata(id: "gpt-4.1-mini", capability: .chatText)]
        )
        var didRequestAdvice = false

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "gpt-4.1-mini",
            latestPrompt: "help me plan",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:9000")!,
            adviceProvider: { _, _ in
                didRequestAdvice = true
                return ProviderModeAdvice(suggestedMode: "plan", confidence: 1, shouldSuggestSwitch: true, currentMode: nil, reason: nil)
            },
            userDecision: { _ in true }
        )

        XCTAssertEqual(modelID, "gpt-4.1-mini")
        XCTAssertFalse(didRequestAdvice)
    }

    func testAdviceSwitchStillSendsAliasNotResolvedModel() async throws {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(
                    id: "mlx-ask",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Ask",
                    role: "ask",
                    compatibilityType: "mlx"
                ),
                ProviderModelMetadata(
                    id: "mlx-coding",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit",
                    role: "coding",
                    compatibilityType: "mlx"
                ),
            ]
        )

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-ask",
            latestPrompt: "implement this",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                ProviderModeAdvice(suggestedMode: "coding", confidence: 0.91, shouldSuggestSwitch: true, currentMode: "ask", reason: "Coding request.")
            },
            userDecision: { _ in true }
        )

        XCTAssertEqual(modelID, "mlx-coding")
        XCTAssertNotEqual(modelID, "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit")
    }

    func testExplicitConcreteModelSelectionIsNotReplacedByAliasMetadata() async throws {
        let catalog = ProviderModelCatalog(
            models: [
                ProviderModelMetadata(
                    id: "mlx-coding",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit",
                    role: "coding",
                    compatibilityType: "mlx"
                ),
                ProviderModelMetadata(
                    id: "mlx-community/Explicit",
                    capability: .chatText,
                    state: "loaded",
                    compatibilityType: "mlx"
                ),
            ]
        )
        var didRequestAdvice = false

        let modelID = await ModeAdviceCoordinator.resolveModelForSend(
            selectedModel: "mlx-community/Explicit",
            latestPrompt: "Implement this directly.",
            catalog: catalog,
            baseURL: URL(string: "http://127.0.0.1:8123")!,
            adviceProvider: { _, _ in
                didRequestAdvice = true
                return ProviderModeAdvice(suggestedMode: "coding", confidence: 0.95, shouldSuggestSwitch: true, currentMode: nil, reason: nil)
            },
            userDecision: { _ in true }
        )

        XCTAssertEqual(modelID, "mlx-community/Explicit")
        XCTAssertFalse(didRequestAdvice)
    }

    private func mlxModeAdviceCatalog() -> ProviderModelCatalog {
        ProviderModelCatalog(
            models: [
                ProviderModelMetadata(
                    id: "mlx-ask",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Ask",
                    role: "ask",
                    compatibilityType: "mlx"
                ),
                ProviderModelMetadata(id: "mlx-plan", capability: .chatText, state: "loaded", role: "plan"),
                ProviderModelMetadata(id: "mlx-coding", capability: .chatText, state: "loaded", role: "coding"),
            ]
        )
    }
}

final class ProviderModelMetadataTests: XCTestCase {
    func testFetchModelListParsesStandardOpenAIModelObjects() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(#"{"object":"list","data":[{"id":"mlx-ask","object":"model"},{"id":"mlx-plan","object":"model"}]}"#.utf8)
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelList()

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.models, [
            ProviderModelMetadata(id: "mlx-ask", capability: .chatText),
            ProviderModelMetadata(id: "mlx-plan", capability: .chatText),
        ])
    }

    func testFetchModelListParsesMLXDashboardAliasMetadata() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-plan","object":"model","resolved_model":"mlx-community/Qwen3.6-35B-A3B-4bit","role":"plan","owned_by":"mlx-community","publisher":"mlx-community","arch":"qwen","quantization":"4bit","compatibility_type":"mlx","generation_type":"text","model_family":"chat","state":"loaded","max_context_length":32768,"future_field":"ignored"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelList()
        let model = try XCTUnwrap(result.models.first)

        XCTAssertEqual(model.id, "mlx-plan")
        XCTAssertEqual(model.resolvedModel, "mlx-community/Qwen3.6-35B-A3B-4bit")
        XCTAssertEqual(model.role, "plan")
        XCTAssertEqual(model.ownedBy, "mlx-community")
        XCTAssertEqual(model.publisher, "mlx-community")
        XCTAssertEqual(model.arch, "qwen")
        XCTAssertEqual(model.quantization, "4bit")
        XCTAssertEqual(model.compatibilityType, "mlx")
        XCTAssertEqual(model.generationType, "text")
        XCTAssertEqual(model.modelFamily, "chat")
        XCTAssertEqual(model.state, "loaded")
        XCTAssertEqual(model.maxContextLength, 32768)
    }

    func testFetchModelMetadataParsesCurrentDashboardNormalChatFieldsAndIgnoresUnknownFields() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"alias","role":"ask","generation_type":"text","model_family":"chat","state":"loaded","resolved_model":"mlx-community/gpt-oss-20b-MXFP4-Q8","runtime":"mlx-lm","model_type":"gpt_oss","supports_streaming":true,"supported_generation_modes":["chat"],"max_context_length":32768,"max_output_tokens":2048,"effective_model":"mlx-community/gpt-oss-20b-MXFP4-Q8","routing_state":"role_endpoint","effective_port":8080,"fallback_reason":null,"future_field":"ignored"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()
        let model = try XCTUnwrap(result.models.first)

        XCTAssertEqual(model.id, "mlx-ask")
        XCTAssertEqual(model.runtime, "mlx-lm")
        XCTAssertEqual(model.modelType, "gpt_oss")
        XCTAssertEqual(model.supportsStreaming, true)
        XCTAssertEqual(model.supportedGenerationModes, ["chat"])
        XCTAssertEqual(model.maxContextLength, 32768)
        XCTAssertEqual(model.maxOutputTokens, 2048)
        XCTAssertEqual(model.effectiveModel, "mlx-community/gpt-oss-20b-MXFP4-Q8")
        XCTAssertEqual(model.routingState, "role_endpoint")
        XCTAssertEqual(model.effectivePort, 8080)
        XCTAssertNil(model.fallbackReason)
    }

    func testFetchModelMetadataParsesDashboardRoutingMetadata() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-coding","type":"alias","role":"coding","generation_type":"text","model_family":"chat","state":"loaded","resolved_model":"mlx-community/Coder","effective_model":"mlx-community/Gemma","routing_state":"active_model_fallback","effective_port":8124,"fallback_reason":"role server unavailable; using active model"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()
        let model = try XCTUnwrap(result.models.first)

        XCTAssertEqual(model.id, "mlx-coding")
        XCTAssertEqual(model.resolvedModel, "mlx-community/Coder")
        XCTAssertEqual(model.effectiveModel, "mlx-community/Gemma")
        XCTAssertEqual(model.routingState, "active_model_fallback")
        XCTAssertEqual(model.effectivePort, 8124)
        XCTAssertEqual(model.fallbackReason, "role server unavailable; using active model")
    }

    func testChatRequestsUseAliasIDNotResolvedModelID() async throws {
        let transport = RecordingTransport(
            response: MockResponse(
                statusCode: 200,
                body: Data(#"{"id":"chat","model":"mlx-plan","choices":[{"index":0,"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
            )
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        _ = try await client.completeChat(
            model: "mlx-plan",
            messages: [ChatTranscriptMessage(role: "user", content: "Plan this")]
        )

        XCTAssertEqual(transport.requestBodies.count, 1)
        XCTAssertTrue(transport.requestBodies[0].contains(#""model":"mlx-plan""#))
        XCTAssertFalse(transport.requestBodies[0].contains("mlx-community/Qwen3.6-35B-A3B-4bit"))
    }

    func testAliasDisplayMetadataExposesUsefulTags() {
        let model = ProviderModelMetadata(
            id: "mlx-coding",
            capability: .chatText,
            state: "loaded",
            resolvedModel: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit",
            role: "coding",
            arch: "devstral",
            quantization: "4bit",
            modelFamily: "chat"
        )

        XCTAssertEqual(model.primaryDisplayName, "mlx-coding")
        XCTAssertEqual(model.secondaryDisplayText, "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit")
        XCTAssertEqual(model.displayTags, ["coding", "devstral", "4bit", "chat", "loaded"])
    }

    func testFetchModelMetadataParsesNormalChatTextModel() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
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
            ProviderModelMetadata(
                id: "mlx-ask",
                capability: .chatText,
                state: "loaded",
                generationType: "text",
                modelFamily: "chat"
            ),
        ])
        XCTAssertEqual(transport.requestKeys, ["GET /provider/v1/models"])
    }

    func testFetchModelMetadataParsesTextDiffusionModel() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
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
                "GET /provider/v1/models": MockResponse(
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

    func testFetchModelMetadataFallsBackToLegacyV0ModelsWhenCanonicalRouteIs404() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
                    statusCode: 404,
                    body: Data(#"{"error":"not found"}"#.utf8)
                ),
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

        XCTAssertEqual(result.models, [
            ProviderModelMetadata(
                id: "mlx-ask",
                capability: .chatText,
                state: "loaded",
                generationType: "text",
                modelFamily: "chat"
            ),
        ])
        XCTAssertEqual(transport.requestKeys, ["GET /provider/v1/models", "GET /api/v0/models"])
    }

    func testFetchModelMetadataFallsBackToLegacyV0ModelsWhenCanonicalRouteIsUnavailable() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /api/v0/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-plan","type":"llm","generation_type":"text","model_family":"chat","state":"loaded"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()

        XCTAssertEqual(result.models, [
            ProviderModelMetadata(
                id: "mlx-plan",
                capability: .chatText,
                state: "loaded",
                generationType: "text",
                modelFamily: "chat"
            ),
        ])
        XCTAssertEqual(transport.requestKeys, ["GET /provider/v1/models", "GET /api/v0/models"])
    }

    func testFetchModelMetadataParsesNotInstalledReasonAsUnsupported() async throws {
        let transport = FakeTransport(
            responses: [
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-community/Devstral","type":"llm","generation_type":"text","model_family":"chat","state":"not_installed","reason":"Model is not installed","not_installed_reason":"Install this model before chatting"}]}"#
                            .utf8
                    )
                ),
            ]
        )
        let client = ProviderClient(baseURL: URL(string: "http://127.0.0.1:8123")!, transport: transport)

        let result = try await client.fetchModelMetadata()

        XCTAssertEqual(
            result.models,
            [
                ProviderModelMetadata(
                    id: "mlx-community/Devstral",
                    capability: .unsupported(reason: "Install this model before chatting"),
                    state: "not_installed",
                    generationType: "text",
                    modelFamily: "chat"
                ),
            ]
        )
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
                "mlx-coding",
            ],
            metadata: [
                ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
            ]
        )

        XCTAssertEqual(catalog.models, [
            ProviderModelMetadata(id: "mlx-ask", capability: .chatText, state: "loaded"),
            ProviderModelMetadata(id: "mlx-coding", capability: .chatText, state: nil),
        ])
    }

    func testModelCatalogOverlaysMetadataOnlyForAdvertisedCanonicalAliases() {
        let catalog = ProviderModelCatalog(
            advertisedModelIDs: [
                "mlx-ask",
                "mlx-plan",
                "mlx-coding",
            ],
            metadata: [
                ProviderModelMetadata(
                    id: "mlx-ask",
                    capability: .chatText,
                    state: "loaded",
                    runtime: "mlx-lm",
                    supportsStreaming: true,
                    effectiveModel: "mlx-community/Ask",
                    routingState: "role_endpoint",
                    effectivePort: 8080
                ),
                ProviderModelMetadata(
                    id: "mlx-plan",
                    capability: .chatText,
                    state: "loaded",
                    resolvedModel: "mlx-community/Plan",
                    role: "plan",
                    maxOutputTokens: 4096
                ),
                ProviderModelMetadata(
                    id: "metadata-only",
                    capability: .chatText,
                    state: "loaded"
                ),
            ]
        )

        XCTAssertEqual(catalog.models.map(\.id), ["mlx-ask", "mlx-plan", "mlx-coding"])
        XCTAssertEqual(catalog.model(id: "mlx-ask")?.effectivePort, 8080)
        XCTAssertEqual(catalog.model(id: "mlx-plan")?.maxOutputTokens, 4096)
        XCTAssertEqual(catalog.model(id: "mlx-coding")?.capability, .chatText)
        XCTAssertNil(catalog.model(id: "metadata-only"))
    }

    func testLegacyFastAliasRemainsSendableOnlyWhenAdvertised() {
        let catalog = ProviderModelCatalog(
            advertisedModelIDs: ["mlx-fast"],
            metadata: [
                ProviderModelMetadata(id: "mlx-fast", capability: .chatText, state: "loaded", role: "coding"),
            ]
        )

        XCTAssertTrue(catalog.canSend(with: "mlx-fast"))
        XCTAssertEqual(catalog.defaultSelection(persistedSelection: ""), "mlx-fast")
    }

    func testFutureMLXDashboardTextDiffusionShapeBuildsRunnableCatalog() async throws {
        let diffusionModel = "mlx-community/Nemotron-Labs-Diffusion-3B-4bit"
        let transport = FakeTransport(
            responses: [
                "GET /v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask"},{"id":"mlx-plan"},{"id":"mlx-coding"},{"id":"mlx-community/Nemotron-Labs-Diffusion-3B-4bit"}]}"#
                            .utf8
                    )
                ),
                "GET /provider/v1/models": MockResponse(
                    statusCode: 200,
                    body: Data(
                        #"{"object":"list","data":[{"id":"mlx-ask","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-plan","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-coding","type":"alias","generation_type":"text","model_family":"chat","state":"loaded"},{"id":"mlx-community/Nemotron-Labs-Diffusion-3B-4bit","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"loaded"},{"id":"mlx-community/diffusiongemma-26B-A4B-it-4bit","type":"llm","generation_type":"text","model_family":"diffusion_text","state":"unsupported","unsupported_reason":"Unsupported by installed mlx-lm runtime"}]}"#
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
            "mlx-coding",
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
        XCTAssertEqual(
            LocalProviderURLValidator.providerURL(from: "http://127.0.0.1:8123/v1")?.absoluteString,
            "http://127.0.0.1:8123"
        )
    }

    func testRejectsRemoteAndUnsupportedProviderURLs() {
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://192.168.1.10:8123"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "https://127.0.0.1:8123"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "https://example.com"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "file:///tmp/provider"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "provider"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://user:pass@127.0.0.1:8123"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://127.0.0.1:8123?token=abc"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://127.0.0.1:8123#fragment"))
        XCTAssertNil(LocalProviderURLValidator.providerURL(from: "http://127.0.0.1:8123/provider/v1/models"))
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

final class MLXChatFileLoggerTests: XCTestCase {
    func testFormatsLogLineWithTimestampLevelAndCategory() {
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            MLXChatFileLogger.formatLine(date: date, level: "notice", category: "provider", message: "Fetched models count=4"),
            "1970-01-01T00:00:00Z notice [provider] Fetched models count=4"
        )
    }

    func testAppendCreatesApplicationSupportLogFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MLXChatFileLoggerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try MLXChatFileLogger.append(
            level: "notice",
            category: "chat",
            message: "Send started model=mlx-coding",
            applicationSupportDirectory: root,
            date: Date(timeIntervalSince1970: 0)
        )

        let logURL = root
            .appending(path: "logs", directoryHint: .isDirectory)
            .appending(path: "mlxchat.log")
        let contents = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertEqual(contents, "1970-01-01T00:00:00Z notice [chat] Send started model=mlx-coding\n")
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
        requestKeys.append(key)

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

final class StreamingRecordingTransport: HTTPStreamingTransport {
    private let statusCode: Int
    private let chunks: [String]
    private(set) var requestPaths: [String] = []
    private(set) var requestBodies: [String] = []

    init(statusCode: Int, chunks: [String]) {
        self.statusCode = statusCode
        self.chunks = chunks
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = chunks.joined()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        return (Data(body.utf8), response)
    }

    func stream(_ request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        requestPaths.append(request.url?.path ?? "")
        requestBodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        let chunks = chunks
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }
        return (stream, response)
    }
}

final class SmokeStreamingTransport: HTTPStreamingTransport {
    private let responses: [String: MockResponse]
    private let streamStatusCode: Int
    private let streamChunks: [String]
    private(set) var requestKeys: [String] = []
    private(set) var streamRequestPaths: [String] = []
    private(set) var streamRequestBodies: [String] = []

    init(
        responses: [String: MockResponse],
        streamStatusCode: Int,
        streamChunks: [String]
    ) {
        self.responses = responses
        self.streamStatusCode = streamStatusCode
        self.streamChunks = streamChunks
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let key = "\(method) \(path)"
        requestKeys.append(key)

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

    func stream(_ request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        streamRequestPaths.append(request.url?.path ?? "")
        streamRequestBodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: streamStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        let chunks = streamChunks
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }
        return (stream, response)
    }
}

final class SequencedRecordingTransport: HTTPTransport {
    private let responses: [MockResponse]
    private var index = 0
    private(set) var requestMethods: [String] = []
    private(set) var requestPaths: [String] = []
    private(set) var requestBodies: [String] = []

    init(responses: [MockResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestMethods.append(request.httpMethod ?? "GET")
        requestPaths.append(request.url?.path ?? "")
        requestBodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")

        guard index < responses.count else {
            throw URLError(.badServerResponse)
        }
        let response = responses[index]
        index += 1

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return (response.body, httpResponse)
    }
}
