import Foundation

public enum OutputFormatter {
    public static func render(_ report: SmokeReport, asJSON: Bool) throws -> String {
        if asJSON {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            return String(decoding: data, as: UTF8.self)
        }

        let passCount = report.checks.filter(\.passed).count
        var lines = [
            "MLXChat Smoke Test Report",
            "Overall: \(report.allPassed ? "PASS" : "FAIL") (\(passCount)/\(report.checks.count) checks)",
            "",
        ]

        for check in report.checks {
            let checkStatus = check.passed ? "[PASS]" : "[FAIL]"
            let statusCode = check.statusCode.map { "status=\($0)" } ?? "no response"
            let model = check.model.map { " model=\($0)" } ?? ""
            let details = check.details.map { " - \($0)" } ?? ""
            lines.append("\(checkStatus) \(check.name) [\(check.route)]\(model) [\(statusCode)]\(details)")
        }

        return lines.joined(separator: "\n")
    }
}
