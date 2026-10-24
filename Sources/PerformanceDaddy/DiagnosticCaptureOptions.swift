import Foundation

struct DiagnosticCaptureOptions: Equatable {
    static let maximumSelectedPIDs = 16
    static let usage = "Usage: --capture-diagnostic <3..120 seconds> <new output.json> [--pid <same-user PID> ...; up to 16]\nSelected-PID mode samples only those same-user PIDs; other processes are unobserved, so it does not establish whole-Mac process coverage. System metrics remain system-wide.\n"

    let duration: TimeInterval
    let outputPath: String
    /// `nil` preserves the existing system process enumeration behavior.
    let selectedSameUserPIDs: [Int32]?
    var includesForegroundEvidence: Bool { selectedSameUserPIDs == nil }

    static func parse(arguments: [String]) -> Self? {
        guard arguments.first == "--capture-diagnostic", arguments.count >= 3,
              let duration = Double(arguments[1]), duration.isFinite, (3...120).contains(duration),
              !arguments[2].isEmpty, !arguments[2].hasPrefix("-") else { return nil }
        var pids: [Int32] = []
        var index = 3
        while index < arguments.count {
            guard arguments[index] == "--pid", index + 1 < arguments.count,
                  arguments[index + 1].allSatisfy(\.isNumber),
                  let pid = Int32(arguments[index + 1]), pid > 0,
                  !pids.contains(pid), pids.count < maximumSelectedPIDs else { return nil }
            pids.append(pid)
            index += 2
        }
        return Self(duration: duration, outputPath: arguments[2],
                    selectedSameUserPIDs: pids.isEmpty ? nil : pids)
    }

    static func hasPIDOption(_ arguments: [String]) -> Bool {
        arguments.contains { $0 == "--pid" || $0.hasPrefix("--pid=") }
    }
}
