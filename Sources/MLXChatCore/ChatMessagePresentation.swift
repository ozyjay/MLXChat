import Foundation

public enum ChatMessagePresentation {
    public static func renderedContent(role: String, content: String) throws -> AttributedString {
        guard role == "assistant" else {
            return AttributedString(content)
        }

        return try AttributedString(markdown: content)
    }
}
