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
    public static func resolveAutomaticAliasForSend(
        baselineAlias: String,
        latestPrompt: String,
        catalog: ProviderModelCatalog,
        baseURL: URL,
        adviceProvider: (String, String) async throws -> ProviderModeAdvice
    ) async -> String {
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
}
