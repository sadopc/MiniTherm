import MiniThermKit
import Foundation

// Root LaunchDaemon: the only part that writes to the SMC. It accepts two commands (fan RPM, auto)
// and always falls back to automatic control when the app goes away or things get hot.

let keepAliveTimeout: TimeInterval = 20
let failsafeTemperature = 100.0

final class Service: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let queue = DispatchQueue(label: "local.minitherm.helper.fan")
    private var manual = false
    private var lastCommand = Date.distantPast
    private let hotKeys = SMC.floatKeys(prefix: "Tp") + SMC.floatKeys(prefix: "Te")

    func setFan(rpm: Double, reply: @escaping (Bool) -> Void) {
        reply(queue.sync {
            guard !overheated() else { restoreAuto(); return false }
            let ok = (0..<Fans.count).allSatisfy { Fans.setManual($0, rpm: rpm) }
            manual = true
            lastCommand = Date()
            return ok
        })
    }

    func setAuto(reply: @escaping (Bool) -> Void) {
        reply(queue.sync { restoreAuto() })
    }

    @discardableResult
    private func restoreAuto() -> Bool {
        manual = false
        return (0..<Fans.count).allSatisfy { Fans.setAuto($0) }
    }

    private func overheated() -> Bool {
        hotKeys.compactMap(SMC.float).contains { $0 >= failsafeTemperature && SensorMap.isPlausible($0) }
    }

    func watchdog() {
        queue.sync {
            guard manual else { return }
            if Date().timeIntervalSince(lastCommand) > keepAliveTimeout || overheated() { restoreAuto() }
        }
    }

    func shutdown() { queue.sync { _ = restoreAuto() } }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // only root or whoever is logged in at the console may drive the fans
        var st = stat()
        let consoleUser = stat("/dev/console", &st) == 0 ? st.st_uid : 0
        guard connection.effectiveUserIdentifier == 0 || connection.effectiveUserIdentifier == consoleUser else { return false }
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.shutdown() }
        connection.resume()
        return true
    }
}

guard SMC.open() else {
    FileHandle.standardError.write(Data("minitherm-helper: cannot open AppleSMC\n".utf8))
    exit(1)
}

let service = Service()

signal(SIGTERM, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { service.shutdown(); exit(0) }
term.resume()

let timer = DispatchSource.makeTimerSource(queue: .global())
timer.schedule(deadline: .now() + 5, repeating: 5)
timer.setEventHandler { service.watchdog() }
timer.resume()

let listener = NSXPCListener(machServiceName: helperMachService)
listener.delegate = service
listener.resume()
RunLoop.main.run()
