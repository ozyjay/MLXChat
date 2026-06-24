import Foundation

public enum ChatMessagePresentation {
    private static let markdownSyntaxCharacters = Set<Character>("\\`*_{}[]()#+-.!|>")

    public static func renderedContent(role: String, content: String) throws -> AttributedString {
        guard role == "assistant" else {
            return AttributedString(content)
        }

        return try AttributedString(
            markdown: readableMarkdownBlocks(from: content),
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }

    private static func readableMarkdownBlocks(from content: String) -> String {
        var lines: [String] = []
        var isInCodeFence = false

        for line in content.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if isCodeFence(trimmedLine) {
                isInCodeFence.toggle()
                continue
            }

            if isInCodeFence {
                lines.append(escapedMarkdownLiteral(line))
                continue
            }

            if isHorizontalRule(trimmedLine) {
                appendBlankLine(to: &lines)
                continue
            }

            if let headingText = headingText(from: line) {
                lines.append(headingText)
                continue
            }

            lines.append(line)
        }

        return normalisedBlankLines(from: lines)
    }

    private static func isCodeFence(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func escapedMarkdownLiteral(_ line: String) -> String {
        var escapedLine = ""
        for character in line {
            if markdownSyntaxCharacters.contains(character) {
                escapedLine.append("\\")
            }
            escapedLine.append(character)
        }
        return escapedLine
    }

    private static func isHorizontalRule(_ trimmedLine: String) -> Bool {
        guard trimmedLine.count >= 3 else { return false }
        return Set(trimmedLine).isSubset(of: ["-"])
            || Set(trimmedLine).isSubset(of: ["*"])
            || Set(trimmedLine).isSubset(of: ["_"])
    }

    private static func headingText(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let markerCount = trimmedLine.prefix(while: { $0 == "#" }).count

        guard (1...6).contains(markerCount) else { return nil }

        let markerEndIndex = trimmedLine.index(trimmedLine.startIndex, offsetBy: markerCount)
        guard markerEndIndex < trimmedLine.endIndex, trimmedLine[markerEndIndex].isWhitespace else {
            return nil
        }

        let textStartIndex = trimmedLine.index(after: markerEndIndex)
        return String(trimmedLine[textStartIndex...])
    }

    private static func appendBlankLine(to lines: inout [String]) {
        guard lines.last?.isEmpty != true else { return }
        lines.append("")
    }

    private static func normalisedBlankLines(from lines: [String]) -> String {
        var result: [String] = []
        var previousWasBlank = false

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank, previousWasBlank {
                continue
            }

            result.append(line)
            previousWasBlank = isBlank
        }

        while result.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeFirst()
        }
        while result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }

        return result.joined(separator: "\n")
    }
}
