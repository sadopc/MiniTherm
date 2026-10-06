import AppKit
import CoreTempKit
import Foundation
import SwiftUI

struct CoreReading: Identifiable {
    let sensor: CoreSensor
    let temperature: Double?
    let usage: Double
    var id: Int { sensor.cpu }
}

enum FanMode: String, CaseIterable, Identifiable {
    case auto, manual, curve
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .auto: return "Auto"
        case .manual: return "Manual"
        case .curve: return "Curve"
        }
    }
}

final class Monitor: ObservableObject {
    static let historyCapacity = 90   // 3 minutes at one sample every 2 s

    @Published private(set) var cores: [CoreReading] = []
    @Published private(set) var gpu: Double?
    @Published private(set) var ssd: Double?
    @Published private(set) var fans: [Fan] = []
    @Published private(set) var history: [Double] = []
    @Published private(set) var helperInstalled = Monitor.helperIsInstalled
    @Published private(set) var installError: String?

    @Published var fanMode = FanMode(rawValue: UserDefaults.standard.string(forKey: "fanMode") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(fanMode.rawValue, forKey: "fanMode"); applyFanMode() }
    }
    @Published var manualRPM = UserDefaults.standard.object(forKey: "manualRPM") as? Double ?? 2000 {
        didSet { UserDefaults.standard.set(manualRPM, forKey: "manualRPM"); applyFanMode() }
    }
    /// Curve mode: fan sits at minimum below `curveStart` and reaches maximum at `curveEnd` (°C, hottest core).
    @Published var curveStart = UserDefaults.standard.object(forKey: "curveStart") as? Double ?? 50 {
        didSet { UserDefaults.standard.set(curveStart, forKey: "curveStart") }
    }
    @Published var curveEnd = UserDefaults.standard.object(forKey: "curveEnd") as? Double ?? 85 {
        didSet { UserDefaults.standard.set(curveEnd, forKey: "curveEnd") }
    }

    let sensors = SensorMap.cores ?? []
    var supported: Bool { !sensors.isEmpty }

    private let gpuKeys: [String]
    private let usage = CPUUsage()
    private var timer: Timer?
    private var connection: NSXPCConnection?

    var hottest: Double? { cores.compactMap(\.temperature).max() }
    var cpuAverage: Double? {
        let t = cores.compactMap(\.temperature)
        return t.isEmpty ? nil : t.reduce(0, +) / Double(t.count)
    }

    var menuTitle: String { hottest.map { "\(Int($0.rounded()))°" } ?? "—" }

    init() {
        _ = SMC.open()
        gpuKeys = SMC.floatKeys(prefix: "Tg")
        tick()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let load = usage.sample()
        cores = sensors.map {
            CoreReading(sensor: $0, temperature: SensorMap.temperature($0), usage: load.indices.contains($0.cpu) ? load[$0.cpu] : 0)
        }
        gpu = SensorMap.average(gpuKeys)
        ssd = SensorMap.ssdKeys.compactMap(SMC.float).filter(SensorMap.isPlausible).max()
        fans = Fans.all()
        if let hot = hottest { history = Array((history + [hot]).suffix(Self.historyCapacity)) }
        applyFanMode()   // doubles as the helper keep-alive
    }

    // MARK: fan control (through the root helper)

    private var targetRPM: Double? {
        guard let fan = fans.first else { return nil }
        switch fanMode {
        case .auto: return nil
        case .manual: return manualRPM
        case .curve:
            guard let hot = hottest, curveEnd > curveStart else { return nil }
            let f = min(max((hot - curveStart) / (curveEnd - curveStart), 0), 1)
            return fan.min + f * (fan.max - fan.min)
        }
    }

    private func applyFanMode() {
        guard helperInstalled else { return }
        if let rpm = targetRPM {
            helper()?.setFan(rpm: rpm) { _ in }
        } else if fans.contains(where: \.manual) {
            helper()?.setAuto { _ in }
        }
    }

    func restoreAuto() {
        if helperInstalled { helper()?.setAuto { _ in } }
    }

    private func helper() -> HelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: helperMachService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            c.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in } as? HelperProtocol
    }

    // MARK: helper installation

    private static let helperBinary = "/Library/PrivilegedHelperTools/\(helperMachService)"
    private static let helperPlist = "/Library/LaunchDaemons/\(helperMachService).plist"
    private static var helperIsInstalled: Bool {
        FileManager.default.fileExists(atPath: helperBinary) && FileManager.default.fileExists(atPath: helperPlist)
    }

    /// Copies the bundled daemon into /Library and starts it. macOS asks for an administrator password once.
    func installHelper() {
        guard let binary = Bundle.main.path(forResource: "coretemp-helper", ofType: nil),
              let plist = Bundle.main.path(forResource: helperMachService, ofType: "plist") else {
            installError = String(localized: "Helper is missing from the app bundle.")
            return
        }
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = [
            "launchctl bootout system/\(helperMachService) 2>/dev/null",
            "mkdir -p /Library/PrivilegedHelperTools"
                + " && install -o root -g wheel -m 755 \(quoted(binary)) \(Self.helperBinary)"
                + " && install -o root -g wheel -m 644 \(quoted(plist)) \(Self.helperPlist)"
                + " && launchctl bootstrap system \(Self.helperPlist)",
        ].joined(separator: "; ")
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        let cancelled = (error?[NSAppleScript.errorNumber] as? Int) == -128
        installError = cancelled ? nil : error?[NSAppleScript.errorMessage] as? String
        helperInstalled = Self.helperIsInstalled
        applyFanMode()
    }
}
