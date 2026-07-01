import Foundation

public enum ChatUsagePresentation {
    public static func latestHeaderUsageState(
        in messages: [ChatDisplayMessage]
    ) -> MLXStreamUsageState? {
        messages
            .reversed()
            .lazy
            .filter { $0.role == "assistant" }
            .compactMap(\.usageState)
            .first { usageState in
                usageState.hasDisplayableUsageData
                    && usageState.displayLines != ["Usage: not reported by provider"]
            }
    }
}
