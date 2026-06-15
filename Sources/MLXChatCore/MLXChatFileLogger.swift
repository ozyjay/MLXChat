import Foundation

public enum MLXChatFileLogger {
    private static let lock = NSLock()

    public static func notice(category: String, _ message: String) {
        try? append(level: "notice", category: category, message: message)
    }

    public static func warning(category: String, _ message: String) {
        try? append(level: "warning", category: category, message: message)
    }

    public static func error(category: String, _ message: String) {
        try? append(level: "error", category: category, message: message)
    }

    public static func debug(category: String, _ message: String) {
        try? append(level: "debug", category: category, message: message)
    }

    public static func append(
        level: String,
        category: String,
        message: String,
        applicationSupportDirectory: URL = defaultApplicationSupportDirectory(),
        date: Date = Date()
    ) throws {
        let logsDirectory = applicationSupportDirectory.appending(path: "logs", directoryHint: .isDirectory)
        let logURL = logsDirectory.appending(path: "mlxchat.log")
        let line = formatLine(date: date, level: level, category: category, message: message) + "\n"
        let data = Data(line.utf8)

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: logURL, options: .atomic)
        }
    }

    public static func formatLine(date: Date, level: String, category: String, message: String) -> String {
        "\(timestampFormatter.string(from: date)) \(level) [\(category)] \(message)"
    }

    public static func defaultApplicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "MLXChat", directoryHint: .isDirectory)
    }

    public static var defaultLogFileURL: URL {
        defaultApplicationSupportDirectory()
            .appending(path: "logs", directoryHint: .isDirectory)
            .appending(path: "mlxchat.log")
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
