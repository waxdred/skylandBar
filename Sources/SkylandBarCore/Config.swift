import Foundation

// skylandbar.toml: the bar as a file instead of a script. Each part becomes the commands a
// sketchybarrc would send (--bar, --default, --add, --set, --subscribe), so a property
// means the same in both, and `ConfigExport` writes a running bar back as such a file.
//
//   hotload = true              --hotload on        (these two first: after a [section],
//   exec = ["~/x/start.sh"]     run with bash once   a key belongs to that section)
//
//   [vars]                      ${name} in any string (then the environment: ${HOME})
//   accent = "0xffcba6f7"
//
//   [bar]                       --bar
//   height = 32
//   color = 0xff1e1e2e          integers given for *color keys are written 0xAARRGGBB
//
//   [defaults]                  --default
//   icon.font = "Hack Nerd Font:Bold:14"
//
//   [[event]]                   --add event <name> [<notification>]
//   name = "theme_changed"
//
//   [[item]]                    in bar order; type: item (default), space, alias, graph,
//   name = "clock"              slider, bracket (members = [...]), workspaces, title, notch
//   position = "right"
//   update_freq = 10
//   script = "sketchybar --set $NAME label=\"$(date '+%H:%M')\""
//   subscribe = ["system_woke"]
//   background = { color = "${accent}", corner_radius = 6 }   tables give dotted keys

public struct ConfigStep: Equatable {
    /// where it comes from, for messages: "[bar]", "item 'clock'"
    public let source: String
    public let arguments: [String]

    public init(source: String, arguments: [String]) {
        self.source = source
        self.arguments = arguments
    }
}

public struct ConfigPlan: Equatable {
    public var steps: [ConfigStep] = []
    /// shell commands to run once it is loaded
    public var exec: [String] = []
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum ConfigFile {
    public static let sections = ["vars", "bar", "defaults", "event", "item", "hotload", "exec"]
    public static let types = ["item", "space", "alias", "graph", "slider", "bracket", "workspaces", "title", "notch"]

    public static func plan(_ text: String, environment: [String: String] = [:]) -> Result<ConfigPlan, ConfigError> {
        let root: TOMLTable
        switch TOML.parse(text) {
            case .success(let table): root = table
            case .failure(let error): return .failure(ConfigError(message: error.description))
        }
        if let unknown = root.keys.first(where: { !sections.contains($0) }) {
            return .failure(ConfigError(message: "unknown section '\(unknown)' (\(sections.joined(separator: ", ")))"))
        }
        var vars: [String: String] = [:]
        if case .table(let table)? = root["vars"] {
            for (key, value) in table.entries { vars[key] = scalar(value, key: key) }
        }
        let fill = { (text: String) in substitute(text, vars, environment) }
        var plan = ConfigPlan()

        for (section, command) in [("bar", "--bar"), ("defaults", "--default")] {
            guard let value = root[section] else { continue }
            guard case .table(let table) = value else { return .failure(ConfigError(message: "[\(section)] must be a table")) }
            let props = properties(table, fill)
            if !props.isEmpty { plan.steps.append(ConfigStep(source: "[\(section)]", arguments: [command] + props)) }
        }

        switch tables(root["event"], "event") {
            case .failure(let error): return .failure(error)
            case .success(let events):
                for event in events {
                    guard case .string(let name)? = event["name"] else { return .failure(ConfigError(message: "[[event]] needs a name")) }
                    var arguments = ["--add", "event", fill(name)]
                    if case .string(let notification)? = event["notification"] { arguments.append(fill(notification)) }
                    plan.steps.append(ConfigStep(source: "event '\(name)'", arguments: arguments))
                }
        }

        switch tables(root["item"], "item") {
            case .failure(let error): return .failure(error)
            case .success(let items):
                for (offset, item) in items.enumerated() {
                    switch step(item, number: offset + 1, fill) {
                        case .success(let step): plan.steps.append(step)
                        case .failure(let error): return .failure(error)
                    }
                }
        }

        if case .bool(true)? = root["hotload"] { plan.steps.append(ConfigStep(source: "hotload", arguments: ["--hotload", "on"])) }
        switch root["exec"] {
            case .string(let command)?: plan.exec = [fill(command)]
            case .array(let commands)?: plan.exec = commands.compactMap { if case .string(let c) = $0 { return fill(c) } else { return nil } }
            default: break
        }
        return .success(plan)
    }

    /// An [[item]]: --add, its properties, its subscriptions, in one message.
    private static func step(_ item: TOMLTable, number: Int, _ fill: (String) -> String) -> Result<ConfigStep, ConfigError> {
        guard case .string(let rawName)? = item["name"] else { return .failure(ConfigError(message: "item #\(number) needs a name")) }
        let name = fill(rawName), source = "item '\(name)'"
        var type = "item"
        if case .string(let given)? = item["type"] { type = given }
        guard types.contains(type) else {
            return .failure(ConfigError(message: "\(source): unknown type '\(type)' (\(types.joined(separator: ", ")))"))
        }
        let rest = TOMLTable.copy(item, without: ["type", "name", "position", "members", "subscribe"])
        let props = properties(rest, fill)
        var arguments = ["--add", type, name]
        switch type {
            case "bracket":
                arguments += strings(item["members"]).map(fill)
                if arguments.count == 3 { return .failure(ConfigError(message: "\(source): a bracket needs members = [...]")) }
            case "notch":
                break
            default:
                guard case .string(let position)? = item["position"] else { return .failure(ConfigError(message: "\(source) needs a position")) }
                arguments.append(fill(position))
                if type == "graph" || type == "slider" { // its width goes with --add
                    let key = "\(type).width="
                    arguments.append(props.first { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) } ?? "100")
                }
        }
        if !props.isEmpty { arguments += ["--set", name] + props }
        let events = strings(item["subscribe"]).map(fill)
        if !events.isEmpty { arguments += ["--subscribe", name] + events }
        return .success(ConfigStep(source: source, arguments: arguments))
    }

    /// An array of tables, or none.
    private static func tables(_ value: TOMLValue?, _ name: String) -> Result<[TOMLTable], ConfigError> {
        guard let value else { return .success([]) }
        guard case .array(let values) = value else { return .failure(ConfigError(message: "'\(name)' must be [[\(name)]] tables")) }
        var result: [TOMLTable] = []
        for value in values {
            guard case .table(let table) = value else { return .failure(ConfigError(message: "'\(name)' must be [[\(name)]] tables")) }
            result.append(table)
        }
        return .success(result)
    }

    private static func strings(_ value: TOMLValue?) -> [String] {
        switch value {
            case .string(let one)?: return [one]
            case .array(let values)?: return values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
            default: return []
        }
    }

    /// "key=value" for each value, nested tables as dotted keys, in file order.
    static func properties(_ table: TOMLTable, _ fill: (String) -> String, prefix: String = "") -> [String] {
        var result: [String] = []
        for (key, value) in table.entries {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if case .table(let nested) = value {
                result += properties(nested, fill, prefix: path)
            } else {
                result.append("\(path)=\(fill(scalar(value, key: path)))")
            }
        }
        return result
    }

    /// A value as the command line writes it: on/off, 0xAARRGGBB for colors, lists with commas.
    static func scalar(_ value: TOMLValue, key: String) -> String {
        switch value {
            case .string(let string): return string
            case .bool(let bool): return bool ? "on" : "off"
            case .integer(let int):
                let last = key.split(separator: ".").last.map(String.init) ?? key
                return last.contains("color") ? String(format: "0x%08x", UInt32(truncatingIfNeeded: int)) : String(int)
            case .float(let double): return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
            case .array(let values): return values.map { scalar($0, key: key) }.joined(separator: ",")
            case .table: return ""
        }
    }

    /// `${name}`: a var, else an environment variable, else left as it is.
    static func substitute(_ text: String, _ vars: [String: String], _ environment: [String: String]) -> String {
        guard text.contains("${") else { return text }
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
            let name = String(rest[start.upperBound ..< end])
            result += vars[name] ?? environment[name] ?? "${\(name)}"
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }
}

extension TOMLTable {
    /// The same entries but `keys`.
    static func copy(_ table: TOMLTable, without keys: Set<String>) -> TOMLTable {
        let copy = TOMLTable()
        for (key, value) in table.entries where !keys.contains(key) { copy.set(key, value) }
        return copy
    }
}

// MARK: export

/// A running bar as skylandbar.toml (`skylandbar --query config`): the bar, the defaults,
/// the events, then every item with what differs from the defaults, in bar order.
public enum ConfigExport {
    public static func toml(_ model: BarModel) -> String {
        var out = "# skylandbar.toml, written by skylandbar --export\n"
        let bar = changes(model.bar.json, from: BarProps().json)
        if !bar.isEmpty { out += "\n[bar]\n" + bar.map(line).joined() }
        let defaults = changes(itemJSON(model.defaults, kind: "item"), from: itemJSON(ItemProps(), kind: "item"))
        if !defaults.isEmpty { out += "\n[defaults]\n" + defaults.map(line).joined() }
        for (name, notification) in model.events.sorted(by: { $0.key < $1.key }) {
            out += "\n[[event]]\nname = \(quote(name))\n"
            if !notification.isEmpty { out += "notification = \(quote(notification))\n" }
        }
        let base = itemJSON(model.defaults, kind: "item")
        for item in model.items where item.kind != "workspace" {
            out += "\n[[item]]\nname = \(quote(item.name))\n"
            if item.kind != "item" { out += "type = \(quote(item.kind))\n" }
            if item.kind == "bracket" {
                out += "members = [\(item.args.map(quote).joined(separator: ", "))]\n"
            } else if item.kind != "notch" {
                out += "position = \(quote(item.props.position))\n"
            }
            if !item.subscriptions.isEmpty { out += "subscribe = [\(item.subscriptions.map(quote).joined(separator: ", "))]\n" }
            var props = changes(itemJSON(item.props, kind: item.kind), from: base).filter { $0.key != "position" }
            for (option, value) in item.options.sorted(by: { $0.key < $1.key }) where option != "open" {
                props.append((key: "\(item.kind).\(option)", value: value))
            }
            for state in workspaceStates {
                for prop in item.states[state] ?? [] { props.append((key: "\(state).\(prop.key)", value: prop.value)) }
            }
            out += props.map(line).joined()
        }
        return out
    }

    /// An item's properties as their keys: geometry, icon, label, scripting, popup, its
    /// component's.
    static func itemJSON(_ props: ItemProps, kind: String) -> [String: Any] {
        var json = props.json
        json["icon"] = props.icon.json
        json["label"] = props.label.json
        json["script"] = props.script
        json["click_script"] = props.clickScript
        json["update_freq"] = props.updateFreq
        json["updates"] = props.updates
        json["mach_helper"] = props.machHelper
        json["popup"] = props.popup.json
        switch kind {
            case "graph": json["graph"] = props.graph.json
            case "slider": json["slider"] = props.slider.json
            case "alias": json["alias"] = props.alias.json
            default: break
        }
        return json
    }

    /// The leaves of `json` that differ from `base`, as dotted keys; a table's `drawing`
    /// comes after its other keys (a color or an image turns drawing on).
    static func changes(_ json: [String: Any], from base: [String: Any], prefix: String = "") -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        let keys = json.keys.sorted { a, b in (a == "drawing" ? 1 : 0, a) < (b == "drawing" ? 1 : 0, b) }
        for key in keys where key != "items" {
            let name = key == "value" ? "string" : key // texts and images show their string as "value"
            let path = prefix.isEmpty ? name : "\(prefix).\(name)"
            if let nested = json[key] as? [String: Any] {
                result += changes(nested, from: base[key] as? [String: Any] ?? [:], prefix: path)
            } else {
                let value = text(json[key]!)
                if base[key].map(text) != value { result.append((key: path, value: value)) }
            }
        }
        return result
    }

    private static func text(_ value: Any) -> String {
        switch value {
            case let double as Double: return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
            case let int as Int: return String(int)
            default: return "\(value)"
        }
    }

    private static func line(_ entry: (key: String, value: String)) -> String { "\(quote(entry.key)) = \(quote(entry.value))\n" }

    /// A TOML basic string.
    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\t": out += "\\t"
                case "\r": out += "\\r"
                default:
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        out += String(format: "\\u%04X", scalar.value)
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
            }
        }
        return out + "\""
    }
}
