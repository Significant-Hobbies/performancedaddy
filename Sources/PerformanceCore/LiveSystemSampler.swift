import Darwin
import Foundation

public protocol SystemSampling: Sendable {
    func sample() async -> SystemSample
    func resetMeasurementWindow() async
}

public actor LiveSystemSampler: SystemSampling {
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var attributionSampler = AttributionSampler()
    private var memoryReader = MemoryEvidenceReader()
    private var diskCapacity = DiskCapacityCache()

    public init() {}

    public func resetMeasurementWindow() async {
        memoryReader = MemoryEvidenceReader()
        diskCapacity.reset()
        previousCPUTicks = nil
        attributionSampler = AttributionSampler()
    }

    public func sample() -> SystemSample {
        sample(includeProcesses: true)
    }

    public func sample(includeProcesses: Bool) -> SystemSample {
        let now = Date()
        let usedCPUCores = readUsedCPUCores()
        let attribution = includeProcesses ? attributionSampler.read() : nil
        let processes = attribution?.processes ?? []
        let samplerCPU = attribution?.observerCPU
        let memory = memoryReader.read()
        let physical = ProcessInfo.processInfo.physicalMemory
        let headroom = memory.flatMap { value -> Double? in
            guard physical > 0 else { return nil }
            return min(1, (Double(value.freeBytes) + Double(value.inactiveBytes)) / Double(physical))
        }

        return SystemSample(
            timestamp: now,
            usedCPUCores: usedCPUCores,
            memoryHeadroomRatio: headroom,
            swapUsedBytes: readSwapUsed(),
            diskFreeBytes: diskCapacity.value(at: now, read: readDiskFree),
            thermal: readThermalCondition(),
            processes: Array(processes.prefix(16)),
            samplerCPUCores: samplerCPU,
            memory: memory,
            power: PowerEvidence.read(),
            workloads: attribution?.workloads
        )
    }

    private func readUsedCPUCores() -> Double? {
        var cpuInfo: processor_info_array_t?
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let values = UnsafeBufferPointer(start: cpuInfo, count: Int(infoCount))
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(values[offset + Int(CPU_STATE_USER)])
            let system = UInt64(values[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(values[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(values[offset + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }

        let current = (busy: busy, total: total)
        defer { previousCPUTicks = current }
        guard let previousCPUTicks,
              total > previousCPUTicks.total,
              busy >= previousCPUTicks.busy
        else { return nil }

        let busyDelta = Double(busy - previousCPUTicks.busy)
        let totalDelta = Double(total - previousCPUTicks.total)
        return (busyDelta / totalDelta) * Double(cpuCount)
    }

    private func readSwapUsed() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    private func readDiskFree() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        return values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
    }

    private func readThermalCondition() -> ThermalCondition {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unavailable
        }
    }
}
