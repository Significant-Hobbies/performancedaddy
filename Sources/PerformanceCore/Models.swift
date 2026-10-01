import Foundation

public enum ThermalCondition: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unavailable
}

public struct ProcessObservation: Codable, Identifiable, Equatable, Sendable {
    public let id: Int32
    public let parentID: Int32
    public let name: String
    public let cpuCores: Double
    public let residentBytes: UInt64

    public init(
        id: Int32,
        parentID: Int32,
        name: String,
        cpuCores: Double,
        residentBytes: UInt64
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.cpuCores = cpuCores
        self.residentBytes = residentBytes
    }
}

public struct SystemSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let usedCPUCores: Double?
    public let memoryHeadroomRatio: Double?
    public let swapUsedBytes: UInt64?
    public let diskFreeBytes: Int64?
    public let thermal: ThermalCondition
    public let processes: [ProcessObservation]
    public let samplerCPUCores: Double?
    public let memory: MemoryEvidence?
    public let power: PowerEvidence?
    public let workloads: [RecordedWorkload]?

    public init(
        timestamp: Date,
        usedCPUCores: Double?,
        memoryHeadroomRatio: Double?,
        swapUsedBytes: UInt64?,
        diskFreeBytes: Int64?,
        thermal: ThermalCondition,
        processes: [ProcessObservation],
        samplerCPUCores: Double? = nil,
        memory: MemoryEvidence? = nil,
        power: PowerEvidence? = nil,
        workloads: [RecordedWorkload]? = nil
    ) {
        self.timestamp = timestamp
        self.usedCPUCores = usedCPUCores
        self.memoryHeadroomRatio = memoryHeadroomRatio
        self.swapUsedBytes = swapUsedBytes
        self.diskFreeBytes = diskFreeBytes
        self.thermal = thermal
        self.processes = processes
        self.samplerCPUCores = samplerCPUCores
        self.memory = memory
        self.power = power
        self.workloads = workloads
    }
}

public struct DiagnosticCapture: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let samples: [SystemSample]
    public let isFixture: Bool

    public init(startedAt: Date, endedAt: Date, samples: [SystemSample], isFixture: Bool = false) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
        self.isFixture = isFixture
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

public enum FindingConfidence: String, Equatable, Sendable {
    case low = "Low confidence"
    case medium = "Medium confidence"
    case high = "High confidence"
}

public enum FindingKind: Equatable, Sendable {
    case temporaryBuildLoad
    case memoryPressure
    case thermalPressure
    case processLoad
    case healthy
    case inconclusive
}

public struct EvidenceItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let isHealthy: Bool
    public let isAvailable: Bool

    public init(id: String, label: String, value: String, isHealthy: Bool, isAvailable: Bool = true) {
        self.id = id
        self.label = label
        self.value = value
        self.isHealthy = isHealthy
        self.isAvailable = isAvailable
    }
}

public struct DiagnosticFinding: Equatable, Sendable {
    public let kind: FindingKind
    public let verdict: String
    public let summary: String
    public let nowTitle: String
    public let nowDetail: String
    public let whyTitle: String
    public let whyDetail: String
    public let nextTitle: String
    public let nextDetail: String
    public let confidence: FindingConfidence
    public let evidence: [EvidenceItem]

    public init(
        kind: FindingKind,
        verdict: String,
        summary: String,
        nowTitle: String,
        nowDetail: String,
        whyTitle: String,
        whyDetail: String,
        nextTitle: String,
        nextDetail: String,
        confidence: FindingConfidence,
        evidence: [EvidenceItem]
    ) {
        self.kind = kind
        self.verdict = verdict
        self.summary = summary
        self.nowTitle = nowTitle
        self.nowDetail = nowDetail
        self.whyTitle = whyTitle
        self.whyDetail = whyDetail
        self.nextTitle = nextTitle
        self.nextDetail = nextDetail
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct DiagnosticReport: Equatable, Sendable {
    public var fanInvestigation: FanInvestigation { FanInvestigation.analyze(capture) }
    public let capture: DiagnosticCapture
    public let finding: DiagnosticFinding
    public let cpuSeries: [Double]
    public let rootCauseAnalysis: RootCauseAnalysis

    public init(capture: DiagnosticCapture, finding: DiagnosticFinding, cpuSeries: [Double]) {
        self.capture = capture
        self.finding = finding
        self.cpuSeries = cpuSeries
        self.rootCauseAnalysis = RootCauseAnalysis.analyze(capture)
    }
}

public enum ComparisonOutcome: String, Equatable, Sendable {
    case improved
    case unchanged
    case worsened
    case inconclusive
}

public struct DiagnosticComparison: Equatable, Sendable {
    public let outcome: ComparisonOutcome
    public let title: String
    public let detail: String
    public let cpuDelta: Double?
    public let memoryHeadroomDelta: Double?

    public init(
        outcome: ComparisonOutcome,
        title: String,
        detail: String,
        cpuDelta: Double?,
        memoryHeadroomDelta: Double?
    ) {
        self.outcome = outcome
        self.title = title
        self.detail = detail
        self.cpuDelta = cpuDelta
        self.memoryHeadroomDelta = memoryHeadroomDelta
    }
}
