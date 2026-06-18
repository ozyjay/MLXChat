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
    public let resolvedModel: String?
    public let role: String?
    public let ownedBy: String?
    public let publisher: String?
    public let arch: String?
    public let quantization: String?
    public let generationType: String?
    public let modelFamily: String?
    public let compatibilityType: String?
    public let maxContextLength: Int?
    public let maxOutputTokens: Int?
    public let runtime: String?
    public let modelType: String?
    public let supportsStreaming: Bool?
    public let supportedGenerationModes: [String]?

    public var isSendableTextModel: Bool {
        capability.isSendableTextModel
    }

    public var primaryDisplayName: String {
        id
    }

    public var secondaryDisplayText: String? {
        resolvedModel
    }

    public var displayTags: [String] {
        [role, arch, quantization, runtime, modelFamily, state]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    public var canStream: Bool {
        supportsStreaming ?? capability == .chatText
    }

    public var supportsDiffusionOptions: Bool {
        capability == .diffusionText
            || supportedGenerationModes?.contains("diffusion") == true
            || supportedGenerationModes?.contains("linear_spec") == true
    }

    public init(
        id: String,
        capability: ProviderModelCapability,
        state: String? = nil,
        resolvedModel: String? = nil,
        role: String? = nil,
        ownedBy: String? = nil,
        publisher: String? = nil,
        arch: String? = nil,
        quantization: String? = nil,
        generationType: String? = nil,
        modelFamily: String? = nil,
        compatibilityType: String? = nil,
        maxContextLength: Int? = nil,
        maxOutputTokens: Int? = nil,
        runtime: String? = nil,
        modelType: String? = nil,
        supportsStreaming: Bool? = nil,
        supportedGenerationModes: [String]? = nil
    ) {
        self.id = id
        self.capability = capability
        self.state = state
        self.resolvedModel = resolvedModel
        self.role = role
        self.ownedBy = ownedBy
        self.publisher = publisher
        self.arch = arch
        self.quantization = quantization
        self.generationType = generationType
        self.modelFamily = modelFamily
        self.compatibilityType = compatibilityType
        self.maxContextLength = maxContextLength
        self.maxOutputTokens = maxOutputTokens
        self.runtime = runtime
        self.modelType = modelType
        self.supportsStreaming = supportsStreaming
        self.supportedGenerationModes = supportedGenerationModes
    }

    public func mergingMetadata(from other: ProviderModelMetadata) -> ProviderModelMetadata {
        ProviderModelMetadata(
            id: id,
            capability: other.capability,
            state: other.state ?? state,
            resolvedModel: other.resolvedModel ?? resolvedModel,
            role: other.role ?? role,
            ownedBy: other.ownedBy ?? ownedBy,
            publisher: other.publisher ?? publisher,
            arch: other.arch ?? arch,
            quantization: other.quantization ?? quantization,
            generationType: other.generationType ?? generationType,
            modelFamily: other.modelFamily ?? modelFamily,
            compatibilityType: other.compatibilityType ?? compatibilityType,
            maxContextLength: other.maxContextLength ?? maxContextLength,
            maxOutputTokens: other.maxOutputTokens ?? maxOutputTokens,
            runtime: other.runtime ?? runtime,
            modelType: other.modelType ?? modelType,
            supportsStreaming: other.supportsStreaming ?? supportsStreaming,
            supportedGenerationModes: other.supportedGenerationModes ?? supportedGenerationModes
        )
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

    public init(advertisedModelIDs: [String], metadata: [ProviderModelMetadata]) {
        self.init(
            advertisedModels: advertisedModelIDs.map {
                ProviderModelMetadata(id: $0, capability: .chatText, state: nil)
            },
            metadata: metadata
        )
    }

    public init(advertisedModels: [ProviderModelMetadata], metadata: [ProviderModelMetadata]) {
        var metadataByID: [String: ProviderModelMetadata] = [:]
        for model in metadata {
            metadataByID[model.id] = model
        }
        self.models = advertisedModels.map { advertised in
            if let modelMetadata = metadataByID[advertised.id] {
                return advertised.mergingMetadata(from: modelMetadata)
            }
            return advertised
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

    public func supportsModeAdvice(baseURL: URL) -> Bool {
        let isDefaultMLXDashboardURL = baseURL.scheme == "http"
            && (baseURL.host == "127.0.0.1" || baseURL.host == "localhost" || baseURL.host == "::1")
            && (baseURL.port ?? 80) == 8123
        if isDefaultMLXDashboardURL {
            return true
        }

        let modeAliases = Set(["mlx-ask", "mlx-plan", "mlx-coding"])
        return models.contains { model in
            modeAliases.contains(model.id)
                && (model.role != nil
                    || model.resolvedModel != nil
                    || model.compatibilityType == "mlx")
        }
    }
}
