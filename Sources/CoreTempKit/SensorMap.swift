import CSMC
import Foundation

public enum Cluster: String, CaseIterable {
    case superCore = "Super"
    case performance = "Performance"
    case efficiency = "Efficiency"
}

public struct CoreSensor {
    public let cpu: Int          // logical CPU number as the scheduler reports it
    public let label: String
    public let cluster: Cluster
    public let keys: [String]
    /// true when the core has no sensor of its own and the value is a cluster average
    public let estimated: Bool

    public init(cpu: Int, label: String, cluster: Cluster, keys: [String], estimated: Bool) {
        self.cpu = cpu; self.label = label; self.cluster = cluster; self.keys = keys; self.estimated = estimated
    }
}

public enum SensorMap {
    public static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// Mac mini (M6, Mac18,5). Found empirically: heat one logical CPU at a time and see which SMC
    /// key rises. Each Super/Performance core has a primary and a secondary sensor (listed in that
    /// order). The Efficiency cluster only exposes three per-core sensors (cpu1–3); cpu0/4/5 show
    /// no dedicated key, so they fall back to the average of those three.
    static let mac18_5: [CoreSensor] = {
        let eAll = ["Te07", "Te08", "Te09"]
        return [
            CoreSensor(cpu: 6, label: "S1", cluster: .superCore, keys: ["Tp0g", "Tp07"], estimated: false),
            CoreSensor(cpu: 7, label: "S2", cluster: .superCore, keys: ["Tp0j", "Tp09"], estimated: false),
            CoreSensor(cpu: 8, label: "P1", cluster: .performance, keys: ["Tp0L", "Tp0G"], estimated: false),
            CoreSensor(cpu: 9, label: "P2", cluster: .performance, keys: ["Tp0I", "Tp0E"], estimated: false),
            CoreSensor(cpu: 10, label: "P3", cluster: .performance, keys: ["Tp0d", "Tp05"], estimated: false),
            CoreSensor(cpu: 11, label: "P4", cluster: .performance, keys: ["Tp0m", "Tp0b"], estimated: false),
            CoreSensor(cpu: 0, label: "E1", cluster: .efficiency, keys: eAll, estimated: true),
            CoreSensor(cpu: 1, label: "E2", cluster: .efficiency, keys: ["Te07"], estimated: false),
            CoreSensor(cpu: 2, label: "E3", cluster: .efficiency, keys: ["Te08"], estimated: false),
            CoreSensor(cpu: 3, label: "E4", cluster: .efficiency, keys: ["Te09"], estimated: false),
            CoreSensor(cpu: 4, label: "E5", cluster: .efficiency, keys: eAll, estimated: true),
            CoreSensor(cpu: 5, label: "E6", cluster: .efficiency, keys: eAll, estimated: true),
        ]
    }()

    /// NAND temperature sensors.
    public static let ssdKeys = ["TH0a", "TH0b", "TH0x"]

    /// Per-core map for this machine, or nil when the model has not been mapped.
    public static var cores: [CoreSensor]? { model == "Mac18,5" ? mac18_5 : nil }

    public static func temperature(_ sensor: CoreSensor) -> Double? {
        let values = sensor.keys.compactMap(SMC.float).filter(isPlausible)
        guard !values.isEmpty else { return nil }
        return sensor.estimated ? values.reduce(0, +) / Double(values.count) : values.max()
    }

    public static func isPlausible(_ t: Double) -> Bool { t > 1 && t < 130 }

    /// Mean of a set of keys, ignoring sensors that are powered down (they read 0).
    public static func average(_ keys: [String]) -> Double? {
        let values = keys.compactMap(SMC.float).filter(isPlausible)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// Per-CPU utilisation between two successive `sample()` calls.
public final class CPUUsage {
    private var lastBusy = [UInt32](repeating: 0, count: 64)
    private var lastIdle = [UInt32](repeating: 0, count: 64)

    public init() { _ = sample() }

    public func sample() -> [Double] {
        var busy = [UInt32](repeating: 0, count: 64), idle = [UInt32](repeating: 0, count: 64)
        let n = Int(cpu_ticks(&busy, &idle, 64))
        guard n > 0 else { return [] }
        defer { lastBusy = busy; lastIdle = idle }
        return (0..<n).map {
            let b = Double(busy[$0] &- lastBusy[$0]), i = Double(idle[$0] &- lastIdle[$0])
            return b + i > 0 ? b / (b + i) : 0
        }
    }
}
