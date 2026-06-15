import Foundation

public enum LocalProviderURLValidator {
    public static func providerURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased()
        else { return nil }

        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard ["127.0.0.1", "localhost", "::1"].contains(normalizedHost) else {
            return nil
        }

        return url
    }
}
