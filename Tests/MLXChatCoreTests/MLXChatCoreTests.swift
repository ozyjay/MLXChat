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
