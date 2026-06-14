import Foundation
import MLXChatCore

@main
struct MLXChatCLI {
    static func main() async {
        do {
            let options = try CLIOptions()

            if options.helpRequested {
                print(CLIOptions.usage)
                return
            }

            let client = ProviderClient(baseURL: options.baseURL, timeout: options.timeout)
            let runner = SmokeTestRunner(client: client)
            let report = await runner.run(includeStreamingCheck: options.runStreamingCheck)
            let output = try OutputFormatter.render(report, asJSON: options.outputJSON)
            print(output)

            exit(report.allPassed ? 0 : 1)
        } catch let error as CLIOptionsError {
            print("Invalid arguments: \(error.localizedDescription)")
            print("")
            print(CLIOptions.usage)
            exit(2)
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
