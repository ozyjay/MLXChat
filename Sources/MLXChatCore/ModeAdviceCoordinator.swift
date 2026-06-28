import Foundation

public struct ProviderModeAdvice: Decodable, Equatable, Sendable {
    public let suggestedMode: String
    public let confidence: Double?
    public let shouldSuggestSwitch: Bool
    public let currentMode: String?
    public let reason: String?

    public init(
        suggestedMode: String,
        confidence: Double?,
        shouldSuggestSwitch: Bool,
        currentMode: String?,
        reason: String?
    ) {
        self.suggestedMode = suggestedMode
        self.confidence = confidence
        self.shouldSuggestSwitch = shouldSuggestSwitch
        self.currentMode = currentMode
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case suggestedMode = "suggested_mode"
        case confidence
        case shouldSuggestSwitch = "should_suggest_switch"
        case currentMode = "current_mode"
        case reason
    }
}

public struct ModeAdviceSwitchPrompt: Equatable, Sendable {
    public let currentModel: String
    public let suggestedMode: String
    public let suggestedModel: String
    public let confidencePercent: Int?
    public let reason: String?

    public init(
        currentModel: String,
        suggestedMode: String,
        suggestedModel: String,
        confidencePercent: Int?,
        reason: String?
    ) {
        self.currentModel = currentModel
        self.suggestedMode = suggestedMode
        self.suggestedModel = suggestedModel
        self.confidencePercent = confidencePercent
        self.reason = reason
    }
}

public enum ModeAdviceCoordinator {
    private static let canonicalModeAliases = ["mlx-ask", "mlx-plan", "mlx-coding"]
    private static let modeAliases = Set(canonicalModeAliases)

    public static func modeAdviceInput(
        from messages: [ChatTranscriptMessage],
        latestPrompt: String
    ) -> String {
        let allowedRoles = Set(["system", "developer", "user"])
        var texts = messages.compactMap { message -> String? in
            guard allowedRoles.contains(message.role) else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return "\(message.role): \(content)"
        }

        let prompt = latestPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texts.isEmpty else {
            return prompt
        }

        if !prompt.isEmpty {
            texts.append("user: \(prompt)")
        }

        return texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func resolveAutomaticAliasForSend(
        baselineAlias: String,
        latestPrompt: String,
        catalog: ProviderModelCatalog,
        baseURL: URL,
        adviceProvider: (String, String) async throws -> ProviderModeAdvice
    ) async -> String {
        guard isModeAlias(baselineAlias) else {
            return baselineAlias
        }
        guard catalog.supportsModeAdvice(baseURL: baseURL) else {
            return baselineAlias
        }

        do {
            let advice = try await adviceProvider(latestPrompt, baselineAlias)
            guard let suggestedAlias = alias(for: advice.suggestedMode),
                  catalog.canSend(with: suggestedAlias)
            else {
                return baselineAlias
            }
            return suggestedAlias
        } catch {
            return baselineAlias
        }
    }

    public static func resolveModelForSend(
        selectedModel: String,
        latestPrompt: String,
        catalog: ProviderModelCatalog,
        baseURL: URL,
        adviceProvider: (String, String) async throws -> ProviderModeAdvice,
        userDecision: @MainActor (ModeAdviceSwitchPrompt) async -> Bool
    ) async -> String {
        guard isModeAlias(selectedModel) else {
            return selectedModel
        }
        guard catalog.supportsModeAdvice(baseURL: baseURL) else {
            return selectedModel
        }

        let advice: ProviderModeAdvice
        do {
            advice = try await adviceProvider(latestPrompt, selectedModel)
        } catch {
            return selectedModel
        }

        guard advice.shouldSuggestSwitch,
              let suggestedModel = alias(for: advice.suggestedMode),
              suggestedModel != selectedModel else {
            return selectedModel
        }

        let prompt = ModeAdviceSwitchPrompt(
            currentModel: selectedModel,
            suggestedMode: advice.suggestedMode,
            suggestedModel: suggestedModel,
            confidencePercent: advice.confidence.map { Int(($0 * 100).rounded()) },
            reason: advice.reason
        )

        let shouldSwitch = await userDecision(prompt)
        return shouldSwitch ? suggestedModel : selectedModel
    }

    public static func alias(for mode: String) -> String? {
        switch mode {
        case "ask":
            return "mlx-ask"
        case "plan":
            return "mlx-plan"
        case "coding":
            return "mlx-coding"
        default:
            return nil
        }
    }

    public static func heuristicAliasForPrompt(
        _ prompt: String,
        baselineAlias: String,
        catalog: ProviderModelCatalog
    ) -> String {
        guard isModeAlias(baselineAlias) else {
            return baselineAlias
        }

        let normalizedPrompt = prompt.lowercased()
        let planningPatterns = [
            "how can i create",
            "how do i create",
            "how to create",
            "how can i build",
            "how do i build",
            "how to build",
            "plan how",
            "plan this",
            "implementation plan",
            "architecture",
            "breakdown",
            "roadmap",
            "sequence",
        ]
        if planningPatterns.contains(where: { normalizedPrompt.contains($0) }),
           catalog.canSend(with: "mlx-plan")
        {
            return "mlx-plan"
        }

        return baselineAlias
    }

    public static func modeSelectionAnnotation(for alias: String) -> ChatTranscriptMessage? {
        switch alias {
        case "mlx-plan":
            return ChatTranscriptMessage(
                role: "system",
                content: """
                Mode: plan. The user explicitly selected planning mode for this request. Treat the following user prompt as a planning request: focus on architecture, sequencing, task decomposition, risks, and next steps before implementation details.
                """
            )
        case "mlx-ask":
            return ChatTranscriptMessage(
                role: "system",
                content: """
                Mode: ask. The user explicitly selected ask mode for this request. Treat the following user prompt as a direct question: answer clearly and avoid turning it into an implementation plan unless the user asks for one.
                """
            )
        case "mlx-coding":
            return ChatTranscriptMessage(
                role: "system",
                content: """
                Mode: coding. The user explicitly selected coding mode for this request. Treat the following user prompt as an implementation request: focus on concrete code, edits, debugging, tests, and verification.
                """
            )
        default:
            return nil
        }
    }

    public static func availableModeChoiceAliases(in catalog: ProviderModelCatalog) -> [String] {
        canonicalModeAliases.filter { catalog.canSend(with: $0) }
    }

    public static func annotatedTranscript(
        _ messages: [ChatTranscriptMessage],
        explicitModeAlias alias: String?
    ) -> [ChatTranscriptMessage] {
        guard let alias,
              let annotation = modeSelectionAnnotation(for: alias)
        else { return messages }

        return [annotation] + messages
    }

    public static func isModeAlias(_ model: String) -> Bool {
        modeAliases.contains(model)
    }
}
