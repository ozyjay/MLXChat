import Foundation

public enum LocalProviderURLValidator {
    private static let loopbackHosts = Set(["127.0.0.1", "localhost", "::1"])

    public static func providerURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue),
              let scheme = components.scheme?.lowercased(),
              scheme == "http",
              let host = components.host?.lowercased()
        else { return nil }

        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard loopbackHosts.contains(normalizedHost),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return nil }

        let normalizedPath = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard normalizedPath.isEmpty || normalizedPath == "v1" else {
            return nil
        }

        components.path = ""
        components.percentEncodedQuery = nil
        components.fragment = nil
        return components.url
    }

    public static func openAIBaseURL(from value: String) -> URL? {
        providerURL(from: value)?.appending(path: "v1")
    }
}
