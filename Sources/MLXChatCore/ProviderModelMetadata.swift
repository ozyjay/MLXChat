import Foundation

public enum ProviderModelCapability: Equatable, Sendable {
    case chatText
    case diffusionText
    case unsupported(reason: String)

    public var isSendableTextModel: Bool {
        switch self {
        case .chatText, .diffusionText:
            return true
        case .unsupported:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .chatText:
            return "Chat"
        case .diffusionText:
            return "Text diffusion"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var unsupportedReason: String? {
        if case .unsupported(let reason) = self {
            return reason
        }
        return nil
    }
}

public struct ProviderModelMetadata: Equatable, Sendable, Identifiable {
    public let id: String
    public let capability: ProviderModelCapability
    public let state: String?

    public var isSendableTextModel: Bool {
        capability.isSendableTextModel
    }

    public init(id: String, capability: ProviderModelCapability, state: String? = nil) {
        self.id = id
        self.capability = capability
        self.state = state
    }
}

public struct ProviderModelCatalog: Equatable, Sendable {
    public let models: [ProviderModelMetadata]

    public init(models: [ProviderModelMetadata]) {
        self.models = models
    }

    public init(modelIDs: [String]) {
        self.models = modelIDs.map {
            ProviderModelMetadata(id: $0, capability: .chatText, state: nil)
        }
    }

    public func model(id: String) -> ProviderModelMetadata? {
        models.first { $0.id == id }
    }

    public func canSend(with modelID: String) -> Bool {
        model(id: modelID)?.isSendableTextModel == true
    }

    public func defaultSelection(persistedSelection: String) -> String {
        if canSend(with: persistedSelection) {
            return persistedSelection
        }
        if canSend(with: "mlx-ask") {
            return "mlx-ask"
        }
        return models.first { $0.isSendableTextModel }?.id ?? ""
    }
}
