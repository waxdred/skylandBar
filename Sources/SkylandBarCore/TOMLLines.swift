import Foundation

// One `key = value` of a TOML config changed in place, so comments, order and formatting
// stay as written (from skyland's settings window, tomlLines.swift). Enough for the settings
// window: scalar values (numbers, booleans, quoted strings without '#'), in a `[section]`
// ("" is the top level) or in an inline table of an `[[item]]` (`notch = { width = 600 }`).

public enum TOMLLines {
    /// Value text of `key` in `[section]`, quotes kept, trailing comment removed.
    public static func value(_ text: String, section: String, key: String) -> String? {
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let name = header(line) { current = name; continue }
            if current == section, let value = lineValue(line, key: key) { return value }
        }
        return nil
    }

    /// `text` with `key` of `[section]` set to `value` (raw TOML: `12`, `true`, `"x"`). A
    /// missing key goes after the section's last key (top level: before the first table); a
    /// missing section is appended.
    public static func set(_ text: String, section: String, key: String, value: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var current = ""
        var lastKeyLine: Int?
        var sectionFound = section == ""
        var firstHeader: Int?
        for (index, line) in lines.enumerated() {
            if let name = header(Substring(line)) {
                if firstHeader == nil { firstHeader = index }
                current = name
                if name == section { sectionFound = true; lastKeyLine = index }
                continue
            }
            guard current == section else { continue }
            if lineValue(Substring(line), key: key) != nil {
                let start = line.range(of: "=")!.upperBound
                let rest = line[start...]
                // the comment as it was, with the spaces before it
                let comment = commentStart(rest).map { hash -> String in
                    let gap = rest[..<hash].reversed().prefix { $0 == " " || $0 == "\t" }
                    return (gap.isEmpty ? " " : String(gap)) + rest[hash...]
                } ?? ""
                lines[index] = String(line[..<start]) + " " + value + comment
                return lines.joined(separator: "\n")
            }
            if line.contains("="), !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { lastKeyLine = index }
        }
        let newLine = "\(key) = \(value)"
        if !sectionFound {
            if lines.last == "" { lines.removeLast() }
            lines += ["", "[\(section)]", newLine, ""]
        } else if let lastKeyLine {
            lines.insert(newLine, at: lastKeyLine + 1)
        } else {
            lines.insert(newLine, at: firstHeader ?? lines.count)
        }
        return lines.joined(separator: "\n")
    }

    /// `text` with `field` set to `value` in the inline table `table = { ... }` of the
    /// `[[item]]` named `item`; nil when there is no such item or table.
    public static func setInline(_ text: String, item: String, table: String, field: String, value: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inItem = false, named = false
        for (index, line) in lines.enumerated() {
            if let name = header(Substring(line)) {
                inItem = name == "[[item]]"
                named = false
                continue
            }
            guard inItem else { continue }
            if let name = lineValue(Substring(line), key: "name"), unquote(name) == item { named = true; continue }
            guard named, let open = line.firstIndex(of: "{"), lineValue(Substring(line[..<open]) + "x", key: table) != nil,
                  let close = closingBrace(line, from: open) else { continue }
            var entries = splitTopLevel(String(line[line.index(after: open) ..< close]))
            if let at = entries.firstIndex(where: { $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == field }) {
                entries[at] = "\(field) = \(value)"
            } else {
                entries.append("\(field) = \(value)")
            }
            lines[index] = String(line[...open]) + " " + entries.joined(separator: ", ") + " " + String(line[close...])
            return lines.joined(separator: "\n")
        }
        return nil
    }

    // MARK: lines

    /// `name` of a `[name]` header line, `[[name]]` for an array of tables header, nil otherwise.
    static func header(_ line: Substring) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[[") { return trimmed }
        guard trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") else { return nil }
        return String(trimmed[trimmed.index(after: trimmed.startIndex) ..< end])
    }

    static func lineValue(_ line: Substring, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key), let equal = trimmed.firstIndex(of: "="),
              trimmed[..<equal].trimmingCharacters(in: .whitespaces) == key else { return nil }
        var value = trimmed[trimmed.index(after: equal)...]
        if let hash = commentStart(value) { value = value[..<hash] }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// First '#' outside quotes.
    static func commentStart(_ text: Substring) -> Substring.Index? {
        var quote: Character?
        for index in text.indices {
            let char = text[index]
            if let open = quote { if char == open { quote = nil } }
            else if char == "'" || char == "\"" { quote = char }
            else if char == "#" { return index }
        }
        return nil
    }

    public static func unquote(_ raw: String) -> String {
        guard raw.count >= 2, let first = raw.first, first == "'" || first == "\"", raw.last == first else { return raw }
        return String(raw.dropFirst().dropLast())
    }

    /// The `}` that closes the `{` at `open`, quotes and nested braces skipped.
    private static func closingBrace(_ line: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var quote: Character?
        for index in line[open...].indices {
            let char = line[index]
            if let q = quote { if char == q { quote = nil }; continue }
            switch char {
                case "'", "\"": quote = char
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return index }
                default: break
            }
        }
        return nil
    }

    /// `a = 1, b = { c = 2 }, d = "x, y"` -> its top-level entries, trimmed.
    private static func splitTopLevel(_ body: String) -> [String] {
        var entries: [String] = []
        var current = "", depth = 0
        var quote: Character?
        for char in body {
            if let q = quote {
                if char == q { quote = nil }
            } else if char == "'" || char == "\"" {
                quote = char
            } else if char == "{" || char == "[" {
                depth += 1
            } else if char == "}" || char == "]" {
                depth -= 1
            } else if char == ",", depth == 0 {
                entries.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(char)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { entries.append(last) }
        return entries
    }
}
