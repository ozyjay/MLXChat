import Foundation

public struct CheckResult: Codable, Equatable {
    public let name: String
    public let route: String
    public let model: String?
    public let passed: Bool
    public let statusCode: Int?
    public let details: String?

    public init(
        name: String,
        route: String,
        model: String? = nil,
        passed: Bool,
        statusCode: Int? = nil,
        details: String? = nil
    ) {
        self.name = name
        self.route = route
        self.model = model
        self.passed = passed
        self.statusCode = statusCode
        self.details = details
    }
}

public struct SmokeReport: Codable {
    public let checks: [CheckResult]
    public let generatedAt: Date
    public let includeStreamingCheck: Bool

    public var allPassed: Bool {
        checks.allSatisfy(\.passed)
    }

    public init(checks: [CheckResult], includeStreamingCheck: Bool) {
        self.checks = checks
        self.generatedAt = Date()
        self.includeStreamingCheck = includeStreamingCheck
    }
}

public struct SmokeTestRunner {
    private let client: ProviderClient
    private let probeModel: String

    public init(client: ProviderClient, probeModel: String = "mlx-ask") {
        self.client = client
        self.probeModel = probeModel
    }

    public func run(includeStreamingCheck: Bool) async -> SmokeReport {
        var checks: [CheckResult] = []
        checks.append(await checkHealth())
        checks.append(await checkModelAliases())
        checks.append(await checkChatCompletions())
        checks.append(await checkResponses())
        if includeStreamingCheck {
            checks.append(await checkChatStream())
        }
        return SmokeReport(checks: checks, includeStreamingCheck: includeStreamingCheck)
    }

    private func checkHealth() async -> CheckResult {
        do {
            let response = try await client.health()
            var passed = false
            if response.isSuccess {
                let payload = try? JSONSerialization.jsonObject(with: response.body)
                let body = payload as? [String: Any]
                passed = body?["status"] as? String == "ok"
            }
            return CheckResult(
                name: "Health",
                route: "/health",
                passed: passed,
                statusCode: response.statusCode,
                details: passed ? "provider healthy" : "unexpected health payload"
            )
        } catch {
            return CheckResult(
                name: "Health",
                route: "/health",
                passed: false,
                details: error.localizedDescription
            )
        }
    }

    private func checkModelAliases() async -> CheckResult {
        do {
            let (models, status) = try await client.fetchModels()
            let missingBaseAliases = ["mlx-ask", "mlx-plan"].filter { !models.contains($0) }
            let hasCanonicalCoding = models.contains("mlx-coding")
            let hasLegacyCoding = models.contains("mlx-fast")
            let passed = missingBaseAliases.isEmpty && (hasCanonicalCoding || hasLegacyCoding)
            let details: String
            if !missingBaseAliases.isEmpty {
                details = "missing aliases: \(missingBaseAliases.joined(separator: ", "))"
            } else if hasCanonicalCoding {
                details = "canonical aliases present"
            } else if hasLegacyCoding {
                details = "legacy mlx-fast coding alias present; upgrade provider to mlx-coding"
            } else {
                details = "missing alias: mlx-coding"
            }
            return CheckResult(
                name: "Models",
                route: "/v1/models",
                passed: passed,
                statusCode: status,
                details: details
            )
        } catch {
            return CheckResult(
                name: "Models",
                route: "/v1/models",
                passed: false,
                details: error.localizedDescription
            )
        }
    }

    private func checkChatCompletions() async -> CheckResult {
        do {
            let response = try await client.chatCompletions(model: probeModel)
            guard response.isSuccess else {
                return CheckResult(
                    name: "Chat completions",
                    route: "/v1/chat/completions",
                    model: probeModel,
                    passed: false,
                    statusCode: response.statusCode,
                    details: "unexpected status"
                )
            }
            let payload = try JSONSerialization.jsonObject(with: response.body)
            let body = payload as? [String: Any]
            let choices = body?["choices"] as? [[String: Any]]
            let hasChoices = choices?.isEmpty == false
            return CheckResult(
                name: "Chat completions",
                route: "/v1/chat/completions",
                model: probeModel,
                passed: hasChoices,
                statusCode: response.statusCode,
                details: hasChoices ? "received completion choices" : "missing choices in response"
            )
        } catch {
            return CheckResult(
                name: "Chat completions",
                route: "/v1/chat/completions",
                model: probeModel,
                passed: false,
                details: error.localizedDescription
            )
        }
    }

    private func checkResponses() async -> CheckResult {
        do {
            let response = try await client.responses(model: probeModel)
            guard response.isSuccess else {
                return CheckResult(
                    name: "Responses",
                    route: "/v1/responses",
                    model: probeModel,
                    passed: false,
                    statusCode: response.statusCode,
                    details: "unexpected status"
                )
            }
            let payload = try JSONSerialization.jsonObject(with: response.body)
            let body = payload as? [String: Any]
            let hasOutput = body?["output"] != nil || body?["choices"] != nil
            return CheckResult(
                name: "Responses",
                route: "/v1/responses",
                model: probeModel,
                passed: hasOutput,
                statusCode: response.statusCode,
                details: hasOutput ? "received response payload" : "missing output or choices"
            )
        } catch {
            return CheckResult(
                name: "Responses",
                route: "/v1/responses",
                model: probeModel,
                passed: false,
                details: error.localizedDescription
            )
        }
    }

    private func checkChatStream() async -> CheckResult {
        do {
            let response = try await client.chatCompletions(model: probeModel, stream: true)
            guard response.isSuccess else {
                return CheckResult(
                    name: "Chat stream",
                    route: "/v1/chat/completions?stream=true",
                    model: probeModel,
                    passed: false,
                    statusCode: response.statusCode,
                    details: "unexpected status"
                )
            }
            let bodyText = String(decoding: response.body, as: UTF8.self)
            let looksLikeStreaming = bodyText.contains("data:")
                || bodyText.contains("[DONE]")
                || bodyText.contains("event:")
            return CheckResult(
                name: "Chat stream",
                route: "/v1/chat/completions?stream=true",
                model: probeModel,
                passed: looksLikeStreaming,
                statusCode: response.statusCode,
                details: looksLikeStreaming ? "streamed chunks returned" : "stream payload was not SSE-like"
            )
        } catch {
            return CheckResult(
                name: "Chat stream",
                route: "/v1/chat/completions?stream=true",
                model: probeModel,
                passed: false,
                details: error.localizedDescription
            )
        }
    }
}
