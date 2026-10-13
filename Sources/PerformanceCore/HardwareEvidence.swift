import Foundation
import NativeInspection

public struct FanEvidence: Codable, Equatable, Sendable {
    public let name: String
    public let rpm: Double?
    public let maximumRPM: Double?
    public var fractionOfMaximum: Double? {
        guard let rpm, let maximumRPM, rpm.isFinite, maximumRPM.isFinite, rpm >= 0, maximumRPM > 0 else { return nil }
        return rpm / maximumRPM
    }
}

public struct HardwareEvidence: Codable, Equatable, Sendable {
    public let fans: [FanEvidence]?
    public let cpuSensorMaximumCelsius: Double?
    public let gpuSensorMaximumCelsius: Double?
    public let cpuSensorCount: Int
    public let gpuSensorCount: Int
    public let gpuUtilizationPercent: Double?
    public let source: String
    public static func valid(_ value: Double, minimum: Double, maximum: Double) -> Double? {
        value.isFinite && value >= minimum && value <= maximum ? value : nil
    }
}

/// Each native connection belongs to this reader, used by one sampling actor.
public final class HardwareEvidenceReader: @unchecked Sendable {
    private let reader = pd_hardware_create()
    public init() {}
    deinit { pd_hardware_destroy(reader) }
    public func read() -> HardwareEvidence {
        var raw = PDHardware(); pd_hardware_read(reader, &raw)
        let current = withUnsafeBytes(of: raw.fan_rpm) { Array($0.bindMemory(to: Double.self)) }
        let maxima = withUnsafeBytes(of: raw.fan_max_rpm) { Array($0.bindMemory(to: Double.self)) }
        let fans: [FanEvidence]? = raw.fan_count >= 0 && raw.fan_count <= 10 ? (0..<Int(raw.fan_count)).map {
            FanEvidence(name: "Fan \($0 + 1)", rpm: HardwareEvidence.valid(current[$0], minimum: 0, maximum: 30000),
                        maximumRPM: HardwareEvidence.valid(maxima[$0], minimum: 1, maximum: 30000))
        } : nil
        return HardwareEvidence(fans: fans,
            cpuSensorMaximumCelsius: HardwareEvidence.valid(raw.cpu_sensor_max_celsius, minimum: 0.01, maximum: 150),
            gpuSensorMaximumCelsius: HardwareEvidence.valid(raw.gpu_sensor_max_celsius, minimum: 0.01, maximum: 150),
            cpuSensorCount: Int(raw.cpu_sensor_count), gpuSensorCount: Int(raw.gpu_sensor_count),
            gpuUtilizationPercent: HardwareEvidence.valid(raw.gpu_percent, minimum: 0, maximum: 100),
            source: "Read-only SMC / IORegistry driver counters; hardware and macOS coverage varies. Sensor maxima are observed readings, not verified chip junction temperatures.")
    }
}
