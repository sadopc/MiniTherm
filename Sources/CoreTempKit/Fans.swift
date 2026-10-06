import Foundation

public struct Fan: Identifiable {
    public let id: Int
    public let actual: Double
    public let target: Double
    public let min: Double
    public let max: Double
    public let manual: Bool
}

/// Fan access through the SMC `F<n>..` keys. On the M6 Mac mini manual control is simply
/// `F0md = 1` followed by `F0Tg = <rpm>` — no `Ftst` unlock step like M3/M4 needed.
public enum Fans {
    public static var count: Int { Int(SMC.uint8("FNum") ?? 0) }

    /// M5/M6 firmware names the mode key `F0md`; earlier machines use `F0Md`.
    static func modeKey(_ i: Int) -> String { SMC.exists("F\(i)md") ? "F\(i)md" : "F\(i)Md" }

    public static func read(_ i: Int) -> Fan? {
        guard let actual = SMC.float("F\(i)Ac"), let min = SMC.float("F\(i)Mn"), let max = SMC.float("F\(i)Mx") else { return nil }
        return Fan(id: i, actual: actual, target: SMC.float("F\(i)Tg") ?? 0, min: min, max: max,
                   manual: (SMC.uint8(modeKey(i)) ?? 0) != 0)
    }

    public static func all() -> [Fan] { (0..<count).compactMap(read) }

    /// Root only. `rpm` is clamped to the fan's own limits.
    public static func setManual(_ i: Int, rpm: Double) -> Bool {
        guard let fan = read(i) else { return false }
        let clamped = Swift.min(Swift.max(rpm, fan.min), fan.max)
        return SMC.write(modeKey(i), uint8: 1) && SMC.write("F\(i)Tg", float: Float(clamped))
    }

    /// Root only. Hands the fan back to the system's thermal controller.
    public static func setAuto(_ i: Int) -> Bool { SMC.write(modeKey(i), uint8: 0) }
}

public let helperMachService = "local.coretemp.helper"

@objc public protocol HelperProtocol {
    /// Puts every fan in manual mode at `rpm` (clamped). Must be repeated periodically as a keep-alive.
    func setFan(rpm: Double, reply: @escaping (Bool) -> Void)
    func setAuto(reply: @escaping (Bool) -> Void)
}
