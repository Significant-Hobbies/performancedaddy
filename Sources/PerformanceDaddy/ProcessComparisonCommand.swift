import Darwin
import Foundation
import PerformanceCore

enum ProcessComparisonCommand {
    static let usage = "Usage: --compare-diagnostic <before.json> <after.json> --pid <PID>\nPrint a JSON comparison for the process observed under this PID in the baseline. Both captures must select that PID on the same Mac boot.\n"

    static func run(arguments: [String]) -> Never {
        if arguments == ["--compare-diagnostic", "--help"] { print(usage, terminator: ""); exit(0) }
        guard arguments.count == 5, arguments[3] == "--pid", let pid = Int32(arguments[4]), pid > 0 else {
            FileHandle.standardError.write(Data(usage.utf8)); exit(2)
        }
        do {
            let result = try ProcessCPUComparison(before: read(arguments[1]), after: read(arguments[2]), pid: pid)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result) + Data([10]))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data(("Comparison unavailable. " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func read(_ path: String) throws -> DiagnosticCapture {
        let fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var metadata = stat()
        let limit = 16 * 1024 * 1024
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size <= limit,
              let data = try file.read(upToCount: limit + 1), data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(DiagnosticCapture.self, from: data)
    }
}
