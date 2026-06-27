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

        let modelList = await checkModelAliases()
        checks.append(modelList.check)

        let metadata = await checkProviderMetadata()
        checks.append(metadata.check)
        checks.append(checkAliasMetadata(advertisedModels: modelList.models, metadata: metadata.models))
        checks.append(checkRoutingMetadata(metadata: metadata.models))

        if shouldCheckModeAdvice(advertisedModels: modelList.models, metadata: metadata.models) {
            checks.append(await checkModeAdvice())
        }

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

    private func checkModelAliases() async -> (check: CheckResult, models: [ProviderModelMetadata]) {
        do {
            let result = try await client.fetchModelList()
            let modelIDs = result.models.map(\.id)
            let requiredAliases = ["mlx-ask", "mlx-plan", "mlx-coding"]
            let missingAliases = requiredAliases.filter { !modelIDs.contains($0) }
            let passed = missingAliases.isEmpty
            let details: String
            if missingAliases.isEmpty {
                details = "canonical aliases present"
            } else if missingAliases == ["mlx-coding"], modelIDs.contains("mlx-fast") {
                details = "missing canonical alias: mlx-coding; legacy mlx-fast is not sufficient"
            } else {
                details = "missing canonical aliases: \(missingAliases.joined(separator: ", "))"
            }
            return (
                CheckResult(
                name: "Models",
                route: "/v1/models",
                passed: passed,
                    statusCode: result.statusCode,
                details: details
                ),
                result.models
            )
        } catch {
            return (
                CheckResult(
                name: "Models",
                route: "/v1/models",
                passed: false,
                details: error.localizedDescription
                ),
                []
            )
        }
    }

    private func checkProviderMetadata() async -> (check: CheckResult, models: [ProviderModelMetadata]) {
        do {
            let result = try await client.fetchCanonicalModelMetadata()
            let passed = !result.models.isEmpty
            return (
                CheckResult(
                    name: "Provider metadata",
                    route: "/provider/v1/models",
                    passed: passed,
                    statusCode: result.statusCode,
                    details: passed
                        ? "received \(result.models.count) metadata rows"
                        : "metadata route returned no models"
                ),
                result.models
            )
        } catch {
            return (
                CheckResult(
                    name: "Provider metadata",
                    route: "/provider/v1/models",
                    passed: false,
                    details: error.localizedDescription
                ),
                []
            )
        }
    }

    private func checkAliasMetadata(
        advertisedModels: [ProviderModelMetadata],
        metadata: [ProviderModelMetadata]
    ) -> CheckResult {
        let advertisedIDs = Set(advertisedModels.map(\.id))
        let requiredAliases = ["mlx-ask": "ask", "mlx-plan": "plan", "mlx-coding": "coding"]
        let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        let advertisedAliases = requiredAliases.keys.filter { advertisedIDs.contains($0) }.sorted()
        let missingMetadata = advertisedAliases.filter { metadataByID[$0] == nil }
        let roleMismatches = advertisedAliases.compactMap { alias -> String? in
            guard let expectedRole = requiredAliases[alias],
                  let role = metadataByID[alias]?.role,
                  !role.isEmpty,
                  role != expectedRole
            else { return nil }
            return "\(alias) role=\(role) expected=\(expectedRole)"
        }

        let passed = missingMetadata.isEmpty && roleMismatches.isEmpty && !advertisedAliases.isEmpty
        let details: String
        if advertisedAliases.isEmpty {
            details = "no canonical aliases were advertised"
        } else if !missingMetadata.isEmpty {
            details = "missing alias metadata: \(missingMetadata.joined(separator: ", "))"
        } else if !roleMismatches.isEmpty {
            details = "alias role mismatch: \(roleMismatches.joined(separator: "; "))"
        } else {
            details = "canonical alias metadata present"
        }

        return CheckResult(
            name: "Alias metadata",
            route: "/provider/v1/models",
            passed: passed,
            details: details
        )
    }

    private func checkRoutingMetadata(metadata: [ProviderModelMetadata]) -> CheckResult {
        let aliasMetadata = metadata.filter { ["mlx-ask", "mlx-plan", "mlx-coding"].contains($0.id) }
        let rowsWithRoutingMetadata = aliasMetadata.filter { model in
            model.effectiveModel != nil
                || model.routingState != nil
                || model.effectivePort != nil
                || model.fallbackReason != nil
        }
        let rowsWithIncompleteRoutingMetadata = rowsWithRoutingMetadata.filter { model in
            model.effectiveModel == nil && model.routingState == nil
        }

        let passed = rowsWithIncompleteRoutingMetadata.isEmpty
        let details: String
        if !passed {
            details = "routing metadata rows missing effective_model/routing_state: \(rowsWithIncompleteRoutingMetadata.map(\.id).joined(separator: ", "))"
        } else if rowsWithRoutingMetadata.isEmpty {
            details = "routing metadata not advertised"
        } else {
            details = "routing metadata present for \(rowsWithRoutingMetadata.map(\.id).joined(separator: ", "))"
        }

        return CheckResult(
            name: "Routing metadata",
            route: "/provider/v1/models",
            passed: passed,
            details: details
        )
    }

    private func shouldCheckModeAdvice(
        advertisedModels: [ProviderModelMetadata],
        metadata: [ProviderModelMetadata]
    ) -> Bool {
        let advertisedIDs = Set(advertisedModels.map(\.id))
        let hasCanonicalAliases = ["mlx-ask", "mlx-plan", "mlx-coding"].allSatisfy {
            advertisedIDs.contains($0)
        }
        let hasDashboardMetadata = metadata.contains { model in
            ["mlx-ask", "mlx-plan", "mlx-coding"].contains(model.id)
                && (model.role != nil
                    || model.resolvedModel != nil
                    || model.effectiveModel != nil
                    || model.compatibilityType == "mlx")
        }
        return hasCanonicalAliases && hasDashboardMetadata
    }

    private func checkModeAdvice() async -> CheckResult {
        do {
            let advice = try await client.fetchModeAdvice(
                input: "help me plan this feature",
                selectedModel: probeModel
            )
            let knownModes = Set(["ask", "plan", "coding", "unknown"])
            let passed = knownModes.contains(advice.suggestedMode)
            let details = passed
                ? "mode advice returned suggested_mode=\(advice.suggestedMode), should_suggest_switch=\(advice.shouldSuggestSwitch)"
                : "unexpected suggested_mode=\(advice.suggestedMode)"
            return CheckResult(
                name: "Mode advice",
                route: "/provider/v1/mode-advice",
                passed: passed,
                details: details
            )
        } catch {
            return CheckResult(
                name: "Mode advice",
                route: "/provider/v1/mode-advice",
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
            var sawContent = false
            var sawUsage = false
            var sawFinishReason = false
            for try await delta in client.streamChat(
                model: probeModel,
                messages: [ChatTranscriptMessage(role: "user", content: "Hello")]
            ) {
                if !delta.content.isEmpty {
                    sawContent = true
                }
                if delta.usageState != nil {
                    sawUsage = true
                }
                if delta.finishReason != nil {
                    sawFinishReason = true
                }
            }
            let passed = sawContent || sawUsage || sawFinishReason
            return CheckResult(
                name: "Chat stream",
                route: "/v1/chat/completions?stream=true",
                model: probeModel,
                passed: passed,
                details: passed
                    ? "stream parser received deltas"
                    : "stream completed without content, usage, or finish metadata"
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
