import Darwin
import Foundation
import NativeInspection
import PerformanceCore
import XCTest

final class WorkloadTests: XCTestCase {
    func testNativeSelfResourceCountersAreAvailableAndMonotonic() {
        var first = PDProcess()
        var second = PDProcess()
        XCTAssertEqual(pd_process(getpid(), &first), 1)
        XCTAssertEqual(pd_process(getpid(), &second), 1)
        XCTAssertEqual(first.started, second.started)
        XCTAssertGreaterThan(first.memory, 0)
        XCTAssertEqual(first.resource_available, 1)
        XCTAssertEqual(second.resource_available, 1)
        XCTAssertGreaterThan(first.footprint, 0)
        XCTAssertGreaterThanOrEqual(second.read_bytes, first.read_bytes)
        XCTAssertGreaterThanOrEqual(second.written_bytes, first.written_bytes)
        var absent = PDProcess()
        XCTAssertEqual(pd_process(Int32.max, &absent), 0)
        XCTAssertEqual(absent.resource_available, 0)
    }

    func testSameProviderWrappersCollapseButSiblingsAndOtherAgentsRemain() {
        let root = process(200, name: "devin")
        let wrapper = process(201, parent: 200, name: "sh")
        let nested = process(202, parent: 201, name: "devin")
        let sibling = process(203, name: "devin")
        let different = process(204, parent: 200, name: "claude")
        let index = WorkloadIndex([root, wrapper, nested, sibling, different])
        XCTAssertEqual(Set(index.agentRoots.map(\.id.pid)), [200, 203, 204])
        XCTAssertEqual(Set(index.descendants(of: root).map(\.id.pid)), [200, 201, 202, 204])
    }

    func testReusedParentPIDDoesNotClaimOlderChild() {
        let parent = process(210, name: "devin", started: 50)
        let child = process(211, parent: 210, started: 10)
        let index = WorkloadIndex([parent, child])
        XCTAssertEqual(index.descendants(of: parent).map(\.id.pid), [210])
        XCTAssertNil(index.agentOwner(of: child))
        XCTAssertTrue(index.descendants(of: process(210, started: 1)).isEmpty)
    }

    func testCyclicAgentsKeepOneDeterministicRoot() {
        let a = process(220, parent: 221, name: "codex")
        let b = process(221, parent: 220, name: "codex")
        let index = WorkloadIndex([b, a])
        XCTAssertEqual(index.agentRoots.map(\.id.pid), [220])
        XCTAssertEqual(index.descendants(of: a).count, 2)
    }

    func testDeepFamilyIsCompleteWithoutRecursiveTraversal() {
        let chain = (1...2_000).map { process(Int32($0), parent: Int32($0 - 1)) }
        let family = WorkloadIndex(chain).descendants(of: chain[0])
        XCTAssertEqual(family.count, 2_000)
        XCTAssertEqual(family.last?.id.pid, 2_000)
    }

    func testKnownAgentExecutableNames() {
        let cases = [("codex", "Codex"), ("claude", "Claude"), ("devin", "Devin"),
                     ("hermes", "Hermes"), ("aider", "Aider"), ("gemini", "Gemini CLI"),
                     ("opencode", "OpenCode"), ("cursor-agent", "Cursor CLI")]
        for (binary, label) in cases {
            XCTAssertEqual(AgentIdentity.label(executable: "/opt/bin/\(binary)", processName: "worker"), label)
            XCTAssertEqual(AgentIdentity.label(executable: "", processName: binary), label)
        }
    }

    func testNativeClaudeVersionedExecutable() {
        let versions = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions").path
        XCTAssertEqual(AgentIdentity.label(executable: "\(versions)/2.1.280", processName: "2.1.280"), "Claude")
        XCTAssertNil(AgentIdentity.label(executable: "/tmp/claude/versions/2.1.280", processName: "2.1.280"))
        XCTAssertNil(AgentIdentity.label(executable: "\(versions)/2.1.280-backup", processName: "2.1.280-backup"))
    }

    func testRunningNativeClaudeProcessesReachAgentGrouping() async throws {
        let versions = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/claude/versions").path + "/"
        let snapshot = await WorkloadSampler().sample()
        let claude = snapshot.processes.filter { $0.executable.hasPrefix(versions) }
        guard !claude.isEmpty else { throw XCTSkip("No native Claude Code process is running") }
        XCTAssertTrue(claude.allSatisfy { $0.agent == "Claude" })
        let index = WorkloadIndex(snapshot.processes)
        XCTAssertTrue(index.agentRoots.contains { $0.agent == "Claude" })
        XCTAssertTrue(claude.allSatisfy { index.agentOwner(of: $0)?.agent == "Claude" })
    }

    func testAgentMatchingRejectsGenericRuntimesAndLookalikes() {
        for name in ["node", "python", "Python", "agent", "Cursor", "CursorUIViewService",
                     "devin-helper", "my-codex", "claude-backup", "hermes-worker", "code"] {
            XCTAssertNil(AgentIdentity.label(executable: "/tmp/\(name)", processName: name), name)
        }
        XCTAssertNil(AgentIdentity.label(executable: "/projects/devin/node", processName: "node"))
    }

    func testDevinFamiliesRemainSeparate() {
        let terminal = process(100, name: "zsh")
        let first = process(101, parent: 100, name: "devin")
        let second = process(102, parent: 100, name: "devin")
        let worker = process(103, parent: 101, name: "node")
        let all = [terminal, first, second, worker]
        XCTAssertEqual(first.agent, "Devin")
        XCTAssertEqual(WorkloadGrouping.agentOwner(of: worker, in: all)?.id, first.id)
        XCTAssertEqual(Set(WorkloadGrouping.descendants(of: first, in: all).map(\.id.pid)), [101, 103])
        XCTAssertEqual(WorkloadGrouping.descendants(of: second, in: all).count, 1)
    }

    private func process(_ pid: Int32, parent: Int32 = 1, name: String = "sleep", started: UInt64 = 10) -> LiveProcess {
        LiveProcess(id: .init(pid: pid, started: started), parent: parent, uid: getuid(), name: name,
                    executable: "/bin/\(name)", directory: "/tmp", cpu: 0, memory: 1024)
    }

    func testAgentGroupingDoesNotMergeSiblingSessionsInOneTerminal() {
        let terminal = process(10, name: "terminal")
        let codex = process(11, parent: 10, name: "codex")
        let claude = process(12, parent: 10, name: "claude")
        let worker = process(13, parent: 11, name: "swift")
        let all = [terminal, codex, claude, worker]
        XCTAssertEqual(WorkloadGrouping.agentOwner(of: worker, in: all)?.id, codex.id)
        XCTAssertEqual(Set(WorkloadGrouping.descendants(of: codex, in: all).map(\.id.pid)), [11, 13])
        XCTAssertNil(WorkloadGrouping.agentOwner(of: terminal, in: all))
    }

    func testAncestryCyclesTerminate() {
        let a = process(20, parent: 21), b = process(21, parent: 20)
        XCTAssertNil(WorkloadGrouping.agentOwner(of: a, in: [a, b]))
        XCTAssertEqual(WorkloadGrouping.descendants(of: a, in: [a, b]).count, 2)
    }

    func testSystemAndSelfCannotBeStopped() {
        XCTAssertNotNil(process(1).stopRestriction)
        XCTAssertNotNil(process(getpid()).stopRestriction)
        XCTAssertTrue(ProcessControl.stop([process(getpid())], force: true)[0].message.hasPrefix("Skipped"))
    }

    func testCPUCounterIsNanosecondsOnAppleSilicon() {
        var before = PDProcess(), after = PDProcess()
        var usageBefore = rusage(), usageAfter = rusage()
        XCTAssertEqual(pd_process(getpid(), &before), 1)
        getrusage(RUSAGE_SELF, &usageBefore)
        var sum = 0.0
        for value in 1...1_000_000 { sum += sin(Double(value)) }
        XCTAssertTrue(sum.isFinite)
        getrusage(RUSAGE_SELF, &usageAfter)
        XCTAssertEqual(pd_process(getpid(), &after), 1)
        func nanoseconds(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1e9
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1000
        }
        let measured = Double(after.cpu - before.cpu)
        let reference = nanoseconds(usageAfter) - nanoseconds(usageBefore)
        XCTAssertGreaterThan(reference, 0)
        XCTAssertGreaterThan(measured / reference, 0.5)
        XCTAssertLessThan(measured / reference, 2)
    }

    func testForceStopIsExplicitAndOnlyTargetsReviewedChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        var native = PDProcess()
        XCTAssertEqual(pd_process(child.processIdentifier, &native), 1)
        let correct = process(child.processIdentifier, started: native.started)
        XCTAssertTrue(ProcessControl.stop([correct], force: true)[0].message.hasPrefix("Force-stop sent"))
        child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }

    func testNativeListenerInventoryIncludesLoopbackTCPAndUDP() throws {
        let tcp = try boundSocket(type: SOCK_STREAM)
        defer { close(tcp.fd) }
        XCTAssertEqual(listen(tcp.fd, 1), 0)
        let udp = try boundSocket(type: SOCK_DGRAM)
        defer { close(udp.fd) }
        var ports = [PDPort](repeating: PDPort(), count: 512)
        var incomplete: Int32 = 0
        let count = ports.withUnsafeMutableBufferPointer { pd_ports(getpid(), $0.baseAddress, 512, &incomplete) }
        XCTAssertTrue(ports.prefix(Int(count)).contains { $0.port == tcp.port && $0.protocol == IPPROTO_TCP && $0.loopback == 1 })
        XCTAssertTrue(ports.prefix(Int(count)).contains { $0.port == udp.port && $0.protocol == IPPROTO_UDP && $0.loopback == 1 })
    }

    func testBackgroundSamplerDropsSocketsAndImmediatelyRestoresOnDemand() async throws {
        let tcp = try boundSocket(type: SOCK_STREAM)
        defer { close(tcp.fd) }
        XCTAssertEqual(listen(tcp.fd, 1), 0)
        let sampler = WorkloadSampler()
        let first = await sampler.sample()
        XCTAssertTrue(try XCTUnwrap(first.processes.first { $0.id.pid == getpid() }).ports.contains { $0.port == tcp.port })
        let background = await sampler.sample(includePorts: false)
        XCTAssertEqual(background.portsDate, .distantPast)
        XCTAssertTrue(background.processes.allSatisfy { $0.ports.isEmpty && $0.portsIncomplete })
        let restored = await sampler.sample()
        XCTAssertGreaterThan(restored.portsDate, background.portsDate)
        XCTAssertTrue(try XCTUnwrap(restored.processes.first { $0.id.pid == getpid() }).ports.contains { $0.port == tcp.port })
    }

    func testStopRejectsReusedPIDAndStopsOnlyReviewedChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        var native = PDProcess()
        XCTAssertEqual(pd_process(child.processIdentifier, &native), 1)
        let stale = process(child.processIdentifier, started: native.started + 1)
        XCTAssertEqual(ProcessControl.stop([stale], force: false)[0].message, "Skipped: process identity changed")
        XCTAssertTrue(child.isRunning)
        let correct = process(child.processIdentifier, started: native.started)
        XCTAssertTrue(ProcessControl.stop([correct], force: false)[0].message.hasPrefix("Stop requested"))
        child.waitUntilExit()
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM)
    }

    func testSamplerRetainsIdleChildAndItsIdentity() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        let snapshot = await WorkloadSampler().sample()
        let item = try XCTUnwrap(snapshot.processes.first { $0.id.pid == child.processIdentifier })
        XCTAssertEqual(item.name, "sleep")
        XCTAssertEqual(item.parent, getpid())
        XCTAssertGreaterThan(item.id.started, 0)
        XCTAssertGreaterThan(snapshot.processes.count, 16)
        XCTAssertGreaterThanOrEqual(snapshot.scanSeconds, 0)
    }

    private func boundSocket(type: Int32) throws -> (fd: Int32, port: UInt16) {
        let fd = socket(AF_INET, type, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { close(fd); throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { close(fd); throw POSIXError(.EIO) }
        return (fd, UInt16(bigEndian: address.sin_port))
    }
}
