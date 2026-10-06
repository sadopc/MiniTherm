import CSMC
import Foundation

/// Thin Swift layer over the AppleSMC user client. Reads work unprivileged; writes need root.
public enum SMC {
    public static func open() -> Bool { smc_open() == 0 }

    static func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    static func name(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .ascii) ?? "????"
    }

    public static func exists(_ key: String) -> Bool {
        var type: UInt32 = 0, size: UInt32 = 0
        return smc_info(code(key), &type, &size) == 0
    }

    /// Apple Silicon stores `flt ` values little-endian.
    public static func float(_ key: String) -> Double? {
        var f: Float = 0
        let ok = withUnsafeMutableBytes(of: &f) { smc_read(code(key), $0.baseAddress, 4) == 0 }
        return ok ? Double(f) : nil
    }

    public static func uint8(_ key: String) -> UInt8? {
        var v: UInt8 = 0
        return smc_read(code(key), &v, 1) == 0 ? v : nil
    }

    public static func write(_ key: String, float: Float) -> Bool {
        var f = float
        return withUnsafeBytes(of: &f) { smc_write(code(key), $0.baseAddress, 4) == 0 }
    }

    public static func write(_ key: String, uint8: UInt8) -> Bool {
        var v = uint8
        return smc_write(code(key), &v, 1) == 0
    }

    /// Every `flt ` key whose name starts with `prefix`.
    public static func floatKeys(prefix: String) -> [String] {
        var count: UInt32 = 0
        guard smc_key_count(&count) == 0 else { return [] }
        var keys: [String] = []
        for i in 0..<count {
            var key: UInt32 = 0, type: UInt32 = 0, size: UInt32 = 0
            guard smc_key_at(i, &key) == 0 else { continue }
            let n = name(key)
            guard n.hasPrefix(prefix), smc_info(key, &type, &size) == 0, type == code("flt ") else { continue }
            keys.append(n)
        }
        return keys
    }
}
