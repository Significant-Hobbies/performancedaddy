import Foundation

public enum PerformanceWorkspaceCommands {
    @MainActor
    public static func handle(arguments: [String]) -> Bool {
        if arguments.first == "--agent-hook" {
            AgentHookCommand.run(arguments: arguments)
            return true
        }
        if arguments.first == "--capture-diagnostic" {
            PerformanceDiagnosticCommand.run(arguments: arguments)
        }
        if arguments.first == "--compare-diagnostic" {
            ProcessComparisonCommand.run(arguments: arguments)
        }
        return false
    }
}
