import Foundation

/// A color: 0xAARRGGBB (also accepted: 0xRRGGBB, #RRGGBB, #AARRGGBB).
public struct ARGB: Equatable, Hashable, CustomStringConvertible {
    public var value: UInt32

    public init(_ value: UInt32) { self.value = value }

    public static let white = ARGB(0xFFFF_FFFF)
    public static let black = ARGB(0xFF00_0000)
    public static let clear = ARGB(0x0000_0000)

    public var alpha: Double { Double(value >> 24 & 0xFF) / 255 }
    public var red: Double { Double(value >> 16 & 0xFF) / 255 }
    public var green: Double { Double(value >> 8 & 0xFF) / 255 }
    public var blue: Double { Double(value & 0xFF) / 255 }

    public static func parse(_ text: String) -> ARGB? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex.removeFirst(2)
        } else if hex.hasPrefix("#") {
            hex.removeFirst()
        } else {
            return nil
        }
        guard hex.count == 8 || hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return ARGB(hex.count == 6 ? 0xFF00_0000 | value : value)
    }

    /// The same color with another opacity (0...1): `color.alpha=0.5`.
    public func withAlpha(_ alpha: Double) -> ARGB {
        let a = UInt32((min(1, max(0, alpha)) * 255).rounded())
        return ARGB(a << 24 | value & 0x00FF_FFFF)
    }

    public var description: String { String(format: "0x%08x", value) }

    /// Channel by channel from `a` (t = 0) to `b` (t = 1).
    public static func mix(_ a: ARGB, _ b: ARGB, _ t: Double) -> ARGB {
        if a == b { return b }
        var result: UInt32 = 0
        for shift in stride(from: 24, through: 0, by: -8) {
            let from = Double(a.value >> UInt32(shift) & 0xFF), to = Double(b.value >> UInt32(shift) & 0xFF)
            let channel = UInt32(min(255, max(0, (from + (to - from) * t).rounded())))
            result |= channel << UInt32(shift)
        }
        return ARGB(result)
    }
}

/// From `a` (t = 0) to `b` (t = 1).
public func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// A font: "Family:Style:Size", e.g. "Hack Nerd Font:Bold:14.0".
public struct FontSpec: Equatable, Hashable, CustomStringConvertible {
    public var family: String
    public var style: String
    public var size: Double

    public init(family: String, style: String, size: Double) {
        self.family = family
        self.style = style
        self.size = size
    }

    /// the default font
    public static let standard = FontSpec(family: "Hack Nerd Font", style: "Bold", size: 14)

    /// "Family:Style:Size"; a part left empty keeps the current one.
    public static func parse(_ text: String, base: FontSpec) -> FontSpec? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 3 else { return nil }
        var font = base
        if !parts[0].isEmpty { font.family = parts[0] }
        if parts.count >= 2, !parts[1].isEmpty { font.style = parts[1] }
        if parts.count == 3, !parts[2].isEmpty {
            guard let size = Double(parts[2]), size > 0 else { return nil }
            font.size = size
        }
        return font
    }

    public var description: String { "\(family):\(style):\(String(format: "%.2f", size))" }
}

/// A rect in points, top-left origin (the bar's own coordinates in queries).
public struct Box: Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Value parsing shared by the property setters. Each setter returns an error message, or
/// nil when the value was taken.
enum Value {
    static func bool(_ text: String, current: Bool) -> Bool? {
        switch text.lowercased() {
            case "on", "yes", "true", "1": return true
            case "off", "no", "false", "0": return false
            case "toggle": return !current
            default: return nil
        }
    }

    static func setBool(_ target: inout Bool, _ text: String) -> String? {
        guard let value = bool(text, current: target) else { return "'\(text)' is not on, off or toggle" }
        target = value
        return nil
    }

    static func setNumber(_ target: inout Double, _ text: String, minimum: Double = -.infinity) -> String? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= minimum else {
            return "'\(text)' is not a number" + (minimum > -.infinity ? " from \(Int(minimum))" : "")
        }
        target = value
        return nil
    }

    /// `color` itself, or `color.alpha` (0...1)
    static func setColor(_ target: inout ARGB, _ text: String, part: String? = nil) -> String? {
        if let part {
            guard part == "alpha" else { return "unknown property" }
            var alpha = 0.0
            if let error = setNumber(&alpha, text, minimum: 0) { return error }
            target = target.withAlpha(alpha)
            return nil
        }
        guard let color = ARGB.parse(text) else { return "'\(text)' is not a color (0xAARRGGBB)" }
        target = color
        return nil
    }

    /// skylandbar's Liquid Glass: off, regular (on) or clear
    static func setGlass(_ target: inout String, _ text: String) -> String? {
        switch text.lowercased() {
            case "on", "yes", "true", "regular": target = "regular"
            case "off", "no", "false": target = "off"
            case "clear": target = "clear"
            case "lens": target = "lens" // a selection inside glass: see GlassShader
            case "toggle": target = target == "off" ? "regular" : "off"
            default: return "'\(text)' is not on, off, regular, clear or lens"
        }
        return nil
    }

    static func oneOf(_ target: inout String, _ text: String, _ allowed: [String]) -> String? {
        guard allowed.contains(text) else { return "'\(text)' is not one of \(allowed.joined(separator: ", "))" }
        target = text
        return nil
    }
}

/// "icon.background.color" -> ("icon", "background.color")
func splitKey(_ key: String) -> (head: String, rest: String?) {
    guard let dot = key.firstIndex(of: ".") else { return (key, nil) }
    return (String(key[..<dot]), String(key[key.index(after: dot)...]))
}

let unknownProperty = "unknown property"
