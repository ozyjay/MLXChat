import Foundation

public enum CLIOptionsError: Error, Equatable, LocalizedError {
    case invalidBaseURLError(String)
    case invalidTimeoutError(String)
    case missingValue(String)
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURLError(value):
            return "Invalid base URL: \(value)"
        case let .invalidTimeoutError(value):
            return "Invalid timeout value: \(value)"
        case let .missingValue(name):
            return "Missing value for \(name)"
        case let .unknownArgument(value):
            return "Unknown argument: \(value)"
        }
    }
}

public struct CLIOptions {
    public let baseURL: URL
    public let timeout: TimeInterval
    public let outputJSON: Bool
    public let runStreamingCheck: Bool
    public let helpRequested: Bool

    public init(arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws {
        var baseURL = URL(string: "http://127.0.0.1:8123")!
        var timeout: TimeInterval = 10
        var outputJSON = false
        var runStreamingCheck = true
        var helpRequested = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                helpRequested = true
            case "--base-url":
                guard index + 1 < arguments.count else {
                    throw CLIOptionsError.missingValue("--base-url")
                }
                let value = arguments[index + 1]
                guard let parsedURL = URL(string: value),
                      let scheme = parsedURL.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      parsedURL.host != nil else {
                    throw CLIOptionsError.invalidBaseURLError(value)
                }
                baseURL = parsedURL
                index += 1
            case "--timeout":
                guard index + 1 < arguments.count else {
                    throw CLIOptionsError.missingValue("--timeout")
                }
                let value = arguments[index + 1]
                guard let parsedTimeout = TimeInterval(value), parsedTimeout > 0 else {
                    throw CLIOptionsError.invalidTimeoutError(value)
                }
                timeout = parsedTimeout
                index += 1
            case "--json":
                outputJSON = true
            case "--no-stream":
                runStreamingCheck = false
            case let unknown where unknown.hasPrefix("-"):
                throw CLIOptionsError.unknownArgument(unknown)
            default:
                throw CLIOptionsError.unknownArgument(argument)
            }
            index += 1
        }

        self.baseURL = baseURL
        self.timeout = timeout
        self.outputJSON = outputJSON
        self.runStreamingCheck = runStreamingCheck
        self.helpRequested = helpRequested
    }

    public static var usage: String {
        return """
        Usage:
          mlxchat [options]

        Options:
          --base-url URL    Base URL for MLX provider (default: http://127.0.0.1:8123)
          --timeout SECS    Request timeout in seconds (default: 10)
          --json            Output JSON report
          --no-stream       Skip streaming chat completion check
          -h, --help        Print this help text
        """
    }
}
