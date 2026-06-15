import Foundation

public enum ProviderLogSanitizer {
    public static func safeBaseURLDescription(_ url: URL) -> String {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.string ?? "<invalid-url>"
    }

    public static func responseSnippet(_ data: Data, maxLength: Int = 240) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<non-utf8 body: \(data.count) bytes>"
        }

        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.count > maxLength else {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: max(0, maxLength - 4))
        return "\(normalized[..<endIndex]) ..."
    }
}
