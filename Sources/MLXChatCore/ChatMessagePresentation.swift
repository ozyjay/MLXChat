import Foundation

public enum ChatContentBlockKind: Equatable, Sendable {
    case paragraph
    case heading
    case numberedListItem
    case bulletListItem
    case unorderedListItem
    case code
    case table
}

public struct ChatContentBlock: Equatable, Sendable {
    public let kind: ChatContentBlockKind
    public let text: String
    public let level: Int?
    public let ordinal: Int?
    public let language: String?
    public let tableRows: [[String]]

    public init(
        kind: ChatContentBlockKind,
        text: String,
        level: Int? = nil,
        ordinal: Int? = nil,
        language: String? = nil,
        tableRows: [[String]] = []
    ) {
        self.kind = kind
        self.text = text
        self.level = level
        self.ordinal = ordinal
        self.language = language
        self.tableRows = tableRows
    }
}

public struct NormalizedAssistantContent: Equatable, Sendable {
    public let content: String
    public let reasoning: String?

    public init(content: String, reasoning: String? = nil) {
        self.content = content
        self.reasoning = reasoning
    }
}

public enum ChatMessagePresentation {
    public static func renderedContent(role: String, content: String) throws -> AttributedString {
        guard role == "assistant" else {
            return AttributedString(content)
        }

        return try AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }

    public static func contentBlocks(role: String, content: String) -> [ChatContentBlock] {
        guard role == "assistant" else {
            return [.init(kind: .paragraph, text: content)]
        }
        return MarkdownBlockParser(content: normalizedAssistantContent(content: content).content).parse()
    }

    public static func normalizedAssistantContent(content: String) -> NormalizedAssistantContent {
        normalizedAssistantContent(content: content, reasoning: nil)
    }

    public static func normalizedAssistantContent(
        content: String,
        reasoning: String?
    ) -> NormalizedAssistantContent {
        guard content.contains("<|channel|>")
            || content.contains("<|message|>")
            || content.contains("<|end|>")
            || content.contains("<|start|>")
        else {
            return NormalizedAssistantContent(content: content, reasoning: emptyToNil(reasoning ?? ""))
        }

        let segments = channelMarkedSegments(from: content)
        let finalTexts = segments
            .filter { segment in
                segment.channel == "final"
                    || (segment.channel != "analysis" && segment.channel != nil)
                    || segment.channel == nil
            }
            .map(\.text)
        let reasoningTexts = segments
            .filter { $0.channel == "analysis" }
            .map(\.text)

        return NormalizedAssistantContent(
            content: joinedMessageText(finalTexts),
            reasoning: joinedReasoning([reasoning, joinedMessageText(reasoningTexts)])
        )
    }

    private static func channelMarkedSegments(from text: String) -> [ChannelMarkedSegment] {
        var segments: [ChannelMarkedSegment] = []
        var cursor = text.startIndex

        func appendPlain(_ substring: Substring) {
            let cleaned = cleanedMarkerText(String(substring))
            guard !cleaned.isEmpty else { return }
            segments.append(ChannelMarkedSegment(channel: nil, text: cleaned))
        }

        while let channelRange = text[cursor...].range(of: "<|channel|>") {
            appendPlain(text[cursor..<channelRange.lowerBound])
            let channelStart = channelRange.upperBound
            guard let messageRange = text[channelStart...].range(of: "<|message|>") else {
                appendPlain(text[channelRange.lowerBound...])
                cursor = text.endIndex
                break
            }

            let channel = String(text[channelStart..<messageRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let messageStart = messageRange.upperBound
            let messageText: String
            if let endRange = text[messageStart...].range(of: "<|end|>") {
                messageText = String(text[messageStart..<endRange.lowerBound])
                cursor = endRange.upperBound
            } else {
                messageText = String(text[messageStart...])
                cursor = text.endIndex
            }

            let cleaned = cleanedMarkerText(messageText)
            if !cleaned.isEmpty {
                segments.append(ChannelMarkedSegment(channel: channel, text: cleaned))
            }
        }

        appendPlain(text[cursor...])
        return segments
    }

    private static func cleanedMarkerText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<|start|>assistant", with: "")
            .replacingOccurrences(of: "<|start|>", with: "")
            .replacingOccurrences(of: "<|channel|>", with: "")
            .replacingOccurrences(of: "<|message|>", with: "")
            .replacingOccurrences(of: "<|end|>", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinedMessageText(_ texts: [String]) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func emptyToNil(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func joinedReasoning(_ values: [String?]) -> String? {
        let text = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return emptyToNil(text)
    }
}

private struct ChannelMarkedSegment {
    let channel: String?
    let text: String
}

private struct MarkdownBlockParser {
    let content: String

    func parse() -> [ChatContentBlock] {
        var blocks: [ChatContentBlock] = []
        var paragraphLines: [String] = []
        let lines = content.components(separatedBy: .newlines)
        var index = 0

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !text.isEmpty {
                blocks.append(.init(kind: .paragraph, text: text))
            }
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = codeFence(from: trimmed) {
                flushParagraph()
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.init(kind: .code, text: codeLines.joined(separator: "\n"), language: fence.language))
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.init(kind: .heading, text: heading.text, level: heading.level))
                index += 1
                continue
            }

            if let table = table(from: lines, startingAt: index) {
                flushParagraph()
                blocks.append(.init(kind: .table, text: "", tableRows: table.rows))
                index = table.nextIndex
                continue
            }

            if let item = numberedListItem(from: trimmed) {
                flushParagraph()
                blocks.append(.init(kind: .numberedListItem, text: item.text, ordinal: item.ordinal))
                index += 1
                continue
            }

            if let text = bulletListItem(from: trimmed) {
                flushParagraph()
                blocks.append(.init(kind: .bulletListItem, text: text))
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private func codeFence(from trimmed: String) -> (marker: String, language: String?)? {
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let marker = String(trimmed.prefix(3))
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (marker, language.isEmpty ? nil : language)
    }

    private func heading(from trimmed: String) -> (level: Int, text: String)? {
        let markerCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let markerEndIndex = trimmed.index(trimmed.startIndex, offsetBy: markerCount)
        guard markerEndIndex < trimmed.endIndex, trimmed[markerEndIndex].isWhitespace else { return nil }
        let textStartIndex = trimmed.index(after: markerEndIndex)
        return (markerCount, String(trimmed[textStartIndex...]))
    }

    private func table(from lines: [String], startingAt index: Int) -> (rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headerLine = lines[index].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard let headerCells = pipeTableCells(from: headerLine),
              let separatorCells = pipeTableCells(from: separatorLine),
              headerCells.count >= 2,
              separatorCells.count == headerCells.count,
              separatorCells.allSatisfy(isTableSeparatorCell)
        else {
            return nil
        }

        var rows = [headerCells]
        var cursor = index + 2
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard let cells = pipeTableCells(from: line), cells.count > 1 else { break }
            rows.append(normalizedTableRow(cells, columnCount: headerCells.count))
            cursor += 1
        }

        return (rows, cursor)
    }

    private func pipeTableCells(from line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var tableLine = line.trimmingCharacters(in: .whitespaces)
        if tableLine.hasPrefix("|") {
            tableLine.removeFirst()
        }
        if tableLine.hasSuffix("|") {
            tableLine.removeLast()
        }
        let cells = tableLine
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count > 1 else { return nil }
        return cells
    }

    private func isTableSeparatorCell(_ text: String) -> Bool {
        var cell = text.trimmingCharacters(in: .whitespaces)
        if cell.hasPrefix(":") {
            cell.removeFirst()
        }
        if cell.hasSuffix(":") {
            cell.removeLast()
        }
        return cell.count >= 3 && cell.allSatisfy { $0 == "-" }
    }

    private func normalizedTableRow(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count == columnCount {
            return cells
        }
        if cells.count > columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    private func numberedListItem(from trimmed: String) -> (ordinal: Int, text: String)? {
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberText = String(trimmed[..<dotIndex])
        guard let ordinal = Int(numberText), ordinal > 0 else { return nil }
        let afterDot = trimmed.index(after: dotIndex)
        guard afterDot < trimmed.endIndex, trimmed[afterDot].isWhitespace else { return nil }
        let textStart = trimmed.index(after: afterDot)
        guard textStart <= trimmed.endIndex else { return nil }
        return (ordinal, String(trimmed[textStart...]))
    }

    private func bulletListItem(from trimmed: String) -> String? {
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
        return String(trimmed.dropFirst(2))
    }
}
