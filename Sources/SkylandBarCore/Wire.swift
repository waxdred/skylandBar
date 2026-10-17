import Foundation

/// sketchybar's Mach messages, as its CLI and SbarLua send them: the arguments, each ended
/// by a NUL, and one more NUL. Events go to a mach_helper as the variables, the same way:
/// "NAME\0clock\0SENDER\0routine\0\0".
public enum Wire {
    public static func arguments(_ data: [UInt8]) -> [String] {
        var parts = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        while parts.last == "" { parts.removeLast() }
        return parts
    }

    public static func message(_ parts: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        for part in parts {
            bytes += Array(part.utf8)
            bytes.append(0)
        }
        bytes.append(0)
        return bytes
    }

    /// The variables, sorted by name.
    public static func event(_ env: [String: String]) -> [UInt8] {
        message(env.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] })
    }
}
