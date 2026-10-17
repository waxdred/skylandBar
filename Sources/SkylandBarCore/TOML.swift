import Foundation

// A TOML reader for skylandbar.toml: tables, arrays of tables, dotted and quoted keys,
// strings (basic, literal, multi-line), integers (decimal, hex, octal, binary), floats,
// booleans, arrays and inline tables; no dates. Tables keep their keys in file order: a
// property set after another applies after it, as on the command line.

public indirect enum TOMLValue {
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table(TOMLTable)
}

public final class TOMLTable {
    public private(set) var keys: [String] = []
    private var values: [String: TOMLValue] = [:]
    /// made by an inline table or a value: no header may add to it
    fileprivate var sealed = false

    public init() {}

    public subscript(key: String) -> TOMLValue? { values[key] }

    public var entries: [(key: String, value: TOMLValue)] { keys.map { ($0, values[$0]!) } }

    func set(_ key: String, _ value: TOMLValue) {
        if values[key] == nil { keys.append(key) }
        values[key] = value
    }
}

public struct TOMLError: Error, Equatable, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

public enum TOML {
    public static func parse(_ text: String) -> Result<TOMLTable, TOMLError> {
        var parser = Parser(Array(text.unicodeScalars))
        do {
            return .success(try parser.document())
        } catch let error as TOMLError {
            return .failure(error)
        } catch {
            return .failure(TOMLError(line: parser.line, message: "\(error)"))
        }
    }
}

private struct Parser {
    let text: [Unicode.Scalar]
    var index = 0
    var line = 1
    let root = TOMLTable()
    /// tables a header or a dotted key made, which a later header may not open again
    var defined = Set<ObjectIdentifier>()

    init(_ text: [Unicode.Scalar]) { self.text = text }

    var current: Unicode.Scalar? { index < text.count ? text[index] : nil }

    func fail(_ message: String) -> TOMLError { TOMLError(line: line, message: message) }

    mutating func advance() {
        if current == "\n" { line += 1 }
        index += 1
    }

    mutating func skipBlanks() { // spaces and tabs
        while let c = current, c == " " || c == "\t" { advance() }
    }

    mutating func skipComment() {
        if current == "#" { while let c = current, c != "\n" { advance() } }
    }

    /// Spaces, comments and new lines (inside arrays).
    mutating func skipAll() {
        while true {
            skipBlanks()
            skipComment()
            if current == "\n" || current == "\r" { advance() } else { return }
        }
    }

    /// The end of a line: only a comment may follow.
    mutating func endLine() throws {
        skipBlanks()
        skipComment()
        if current == "\r" { advance() }
        guard current == nil || current == "\n" else { throw fail("unexpected '\(current!)' after the value") }
        if current == "\n" { advance() }
    }

    mutating func document() throws -> TOMLTable {
        var table = root
        while true {
            skipAll()
            guard let c = current else { return root }
            if c == "[" {
                table = try header()
            } else {
                try keyValue(into: table)
            }
        }
    }

    /// `[a.b]` or `[[a.b]]`: the table the next keys go to.
    mutating func header() throws -> TOMLTable {
        advance()
        let isArray = current == "["
        if isArray { advance() }
        skipBlanks()
        let path = try key()
        skipBlanks()
        guard current == "]" else { throw fail("expected ']' after the table name") }
        advance()
        if isArray {
            guard current == "]" else { throw fail("expected ']]' after the table name") }
            advance()
        }
        try endLine()
        var table = root
        for (offset, part) in path.enumerated() {
            let last = offset == path.count - 1
            switch table[part] {
                case nil:
                    if last && isArray {
                        let new = TOMLTable()
                        table.set(part, .array([.table(new)]))
                        return new
                    }
                    let new = TOMLTable()
                    table.set(part, .table(new))
                    table = new
                case .table(let existing)?:
                    if last && isArray { throw fail("'\(part)' is a table, not an array of tables") }
                    if existing.sealed || (last && defined.contains(ObjectIdentifier(existing))) { throw fail("table '\(path.joined(separator: "."))' is defined twice") }
                    table = existing
                case .array(var tables)?:
                    guard case .table(let lastTable)? = tables.last, !lastTable.sealed else { throw fail("'\(part)' is an array of values") }
                    if last && isArray {
                        let new = TOMLTable()
                        tables.append(.table(new))
                        table.set(part, .array(tables))
                        return new
                    }
                    if last { throw fail("'\(part)' is an array of tables: use [[\(path.joined(separator: "."))]]") }
                    table = lastTable
                default:
                    throw fail("'\(part)' already has a value")
            }
        }
        defined.insert(ObjectIdentifier(table))
        return table
    }

    mutating func keyValue(into table: TOMLTable) throws {
        try pair(into: table)
        try endLine()
    }

    /// `a.b = value`
    mutating func pair(into table: TOMLTable) throws {
        let path = try key()
        skipBlanks()
        guard current == "=" else { throw fail("expected '=' after the key '\(path.joined(separator: "."))'") }
        advance()
        skipBlanks()
        let value = try self.value()
        var target = table
        for part in path.dropLast() {
            switch target[part] {
                case nil:
                    let new = TOMLTable()
                    target.set(part, .table(new))
                    target = new
                case .table(let existing)? where !existing.sealed:
                    target = existing
                default:
                    throw fail("'\(part)' already has a value")
            }
        }
        let name = path[path.count - 1]
        guard target[name] == nil else { throw fail("'\(path.joined(separator: "."))' is set twice") }
        target.set(name, value)
    }

    /// A dotted key: bare (A-Z a-z 0-9 _ -) or quoted parts.
    mutating func key() throws -> [String] {
        var parts: [String] = []
        while true {
            skipBlanks()
            guard let c = current else { throw fail("expected a key") }
            if c == "\"" || c == "'" {
                parts.append(try string())
            } else {
                var part = ""
                while let c = current, Self.isBareKey(c) {
                    part.unicodeScalars.append(c)
                    advance()
                }
                guard !part.isEmpty else { throw fail("expected a key, found '\(c)'") }
                parts.append(part)
            }
            skipBlanks()
            guard current == "." else { return parts }
            advance()
        }
    }

    static func isBareKey(_ c: Unicode.Scalar) -> Bool {
        (48 ... 57).contains(c.value) || (65 ... 90).contains(c.value) || (97 ... 122).contains(c.value) || c == "_" || c == "-"
    }

    mutating func value() throws -> TOMLValue {
        guard let c = current else { throw fail("expected a value") }
        switch c {
            case "\"", "'": return .string(try string())
            case "[": return try array()
            case "{": return try inlineTable()
            case "t", "f": return try boolean()
            default: return try number()
        }
    }

    mutating func boolean() throws -> TOMLValue {
        for (word, value) in [("true", true), ("false", false)] {
            let scalars = Array(word.unicodeScalars)
            if index + scalars.count <= text.count, Array(text[index ..< index + scalars.count]) == scalars {
                index += scalars.count
                return .bool(value)
            }
        }
        throw fail("expected a value")
    }

    mutating func number() throws -> TOMLValue {
        var raw = ""
        while let c = current, !" \t\r\n,]}#".unicodeScalars.contains(c) {
            raw.unicodeScalars.append(c)
            advance()
        }
        let clean = raw.replacingOccurrences(of: "_", with: "")
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where clean.hasPrefix(prefix) {
            guard let value = Int64(clean.dropFirst(2), radix: radix) else { break }
            return .integer(value)
        }
        if let value = Int64(clean) { return .integer(value) }
        switch clean {
            case "inf", "+inf": return .float(.infinity)
            case "-inf": return .float(-.infinity)
            case "nan", "+nan", "-nan": return .float(.nan)
            default: break
        }
        if let value = Double(clean), clean.contains(where: { ".eE".contains($0) }) { return .float(value) }
        throw fail(raw.isEmpty ? "expected a value" : "'\(raw)' is not a value (strings go in quotes)")
    }

    mutating func array() throws -> TOMLValue {
        advance()
        var values: [TOMLValue] = []
        while true {
            skipAll()
            if current == "]" {
                advance()
                return .array(values)
            }
            let value = try self.value()
            if case .table(let table) = value { table.sealed = true }
            values.append(value)
            skipAll()
            if current == "," {
                advance()
            } else if current != "]" {
                throw fail("expected ',' or ']' in the array")
            }
        }
    }

    mutating func inlineTable() throws -> TOMLValue {
        advance()
        let table = TOMLTable()
        skipBlanks()
        if current == "}" {
            advance()
            table.sealed = true
            return .table(table)
        }
        while true {
            try pair(into: table)
            skipBlanks()
            if current == "}" {
                advance()
                table.sealed = true
                return .table(table)
            }
            guard current == "," else { throw fail("expected ',' or '}' in the inline table") }
            advance()
            skipBlanks()
        }
    }

    /// A basic ("..."), literal ('...') or multi-line ("""...""", '''...''') string.
    mutating func string() throws -> String {
        let quote = current!
        let literal = quote == "'"
        var multiline = false
        if index + 2 < text.count, text[index + 1] == quote, text[index + 2] == quote {
            multiline = true
            index += 3
            if current == "\r" { advance() }
            if current == "\n" { advance() } // a new line right after the quotes is not part of it
        } else {
            advance()
        }
        var result = ""
        while true {
            guard let c = current else { throw fail("the string is not closed") }
            if c == quote {
                if !multiline {
                    advance()
                    return result
                }
                var run = 0
                while index + run < text.count, text[index + run] == quote { run += 1 }
                if run >= 3 { // the end; up to two more quotes before it belong to the string
                    for _ in 0 ..< min(run - 3, 2) { result.unicodeScalars.append(quote) }
                    index += min(run, 5)
                    return result
                }
                result.unicodeScalars.append(c)
                advance()
                continue
            }
            if c == "\n" && !multiline { throw fail("a new line in a string (use \"\"\" for several lines)") }
            if c == "\\" && !literal {
                advance()
                guard let escaped = current else { throw fail("the string is not closed") }
                switch escaped {
                    case "n": result += "\n"
                    case "t": result += "\t"
                    case "r": result += "\r"
                    case "b": result += "\u{8}"
                    case "f": result += "\u{C}"
                    case "e": result += "\u{1B}"
                    case "\"": result += "\""
                    case "\\": result += "\\"
                    case "u", "U":
                        let count = escaped == "u" ? 4 : 8
                        guard index + count < text.count,
                              let code = UInt32(String(String.UnicodeScalarView(text[index + 1 ... index + count])), radix: 16),
                              let scalar = Unicode.Scalar(code) else { throw fail("a bad \\\(escaped) escape") }
                        result.unicodeScalars.append(scalar)
                        index += count
                    case "\n", " ", "\t", "\r": // a line ending backslash: the next blanks go
                        guard multiline else { throw fail("unknown escape \\ followed by a blank") }
                        while let next = current, next == " " || next == "\t" || next == "\n" || next == "\r" { advance() }
                        continue
                    default:
                        throw fail("unknown escape \\\(escaped)")
                }
                advance()
                continue
            }
            result.unicodeScalars.append(c)
            advance()
        }
    }
}
