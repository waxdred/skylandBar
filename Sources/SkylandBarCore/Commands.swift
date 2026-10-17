import Foundation

/// `key=value`, as in `--set clock label=12:00`.
public struct Prop: Equatable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

/// One command. A message (one `skylandbar ...` call) holds several:
/// `skylandbar --add item clock right --set clock update_freq=10 script="..."`.
public enum Command: Equatable {
    case bar([Prop])
    /// item, event, bracket, graph, slider, alias, space
    case add(kind: String, name: String, args: [String])
    case set(target: String, [Prop])
    case defaults([Prop])
    case subscribe(target: String, events: [String])
    case trigger(event: String, env: [Prop])
    case remove(target: String)
    case move(name: String, before: Bool, reference: String)
    case reorder([String])
    case rename(from: String, to: String)
    case clone(name: String, parent: String, placement: String?)
    case push(name: String, values: [String])
    case animate(curve: String, duration: Double)
    case query(String)
    case update
    case reload(path: String?)
    case hotload(Bool)
    /// the settings window: the config file in an editor
    case settings
    case exit
}

public struct CommandError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum CommandParser {
    /// The commands of one message: each starts with a `--` word and takes the words up to
    /// the next one.
    public static func parse(_ arguments: [String]) -> Result<[Command], CommandError> {
        var groups: [(name: String, args: [String])] = []
        for word in arguments {
            if word.hasPrefix("--") && word.count > 2 {
                groups.append((word, []))
            } else if groups.isEmpty {
                return .failure(CommandError("'\(word)' is not a command (they start with --)"))
            } else {
                groups[groups.count - 1].args.append(word)
            }
        }
        var commands: [Command] = []
        for group in groups {
            switch command(group.name, group.args) {
                case .success(let command): commands.append(command)
                case .failure(let error): return .failure(error)
            }
        }
        return .success(commands)
    }

    static func command(_ name: String, _ args: [String]) -> Result<Command, CommandError> {
        func need(_ count: Int, _ usage: String) -> CommandError? {
            args.count >= count ? nil : CommandError("\(name): expected \(usage)")
        }
        switch name {
            case "--bar":
                return props(args, name).map { .bar($0) }
            case "--add":
                if let error = need(2, "<item|event|bracket|graph|slider|alias|space|workspaces|title|notch> <name> ...") { return .failure(error) }
                let kind = args[0], itemName = args[1], rest = Array(args.dropFirst(2))
                switch kind {
                    case "item", "alias", "space", "workspaces", "title":
                        guard rest.count == 1 else { return .failure(CommandError("--add \(kind): expected <name> <position>")) }
                    case "graph", "slider":
                        guard rest.count == 2, Double(rest[1]) != nil else {
                            return .failure(CommandError("--add \(kind): expected <name> <position> <width>"))
                        }
                    case "notch":
                        guard rest.isEmpty else { return .failure(CommandError("--add notch: expected <name>")) }
                    case "event":
                        guard rest.count <= 1 else { return .failure(CommandError("--add event: expected <name> [<NSDistributedNotification name>]")) }
                    case "bracket":
                        break
                    default:
                        return .failure(CommandError("--add: unknown kind '\(kind)'"))
                }
                return .success(.add(kind: kind, name: itemName, args: rest))
            case "--set":
                if let error = need(1, "<name or /regex/> <property=value> ...") { return .failure(error) }
                return props(Array(args.dropFirst()), name).map { .set(target: args[0], $0) }
            case "--default", "--defaults":
                return props(args, name).map { .defaults($0) }
            case "--subscribe":
                if let error = need(2, "<name or /regex/> <event> ...") { return .failure(error) }
                return .success(.subscribe(target: args[0], events: Array(args.dropFirst())))
            case "--trigger":
                if let error = need(1, "<event> [<VAR=value> ...]") { return .failure(error) }
                return props(Array(args.dropFirst()), name).map { .trigger(event: args[0], env: $0) }
            case "--remove":
                if let error = need(1, "<name or /regex/>") { return .failure(error) }
                return .success(.remove(target: args[0]))
            case "--move":
                guard args.count == 3, args[1] == "before" || args[1] == "after" else {
                    return .failure(CommandError("--move: expected <name> before|after <reference>"))
                }
                return .success(.move(name: args[0], before: args[1] == "before", reference: args[2]))
            case "--reorder":
                if let error = need(1, "<name> ...") { return .failure(error) }
                return .success(.reorder(args))
            case "--rename":
                guard args.count == 2 else { return .failure(CommandError("--rename: expected <name> <new name>")) }
                return .success(.rename(from: args[0], to: args[1]))
            case "--clone":
                guard args.count == 2 || (args.count == 3 && (args[2] == "before" || args[2] == "after")) else {
                    return .failure(CommandError("--clone: expected <name> <parent> [before|after]"))
                }
                return .success(.clone(name: args[0], parent: args[1], placement: args.count == 3 ? args[2] : nil))
            case "--push":
                if let error = need(1, "<name> <value> ...") { return .failure(error) }
                return .success(.push(name: args[0], values: Array(args.dropFirst())))
            case "--animate":
                guard args.count == 2, let duration = Double(args[1]), duration >= 0 else {
                    return .failure(CommandError("--animate: expected <linear|quadratic|tanh|sin|exp|circ> <duration in frames>"))
                }
                return .success(.animate(curve: args[0], duration: duration))
            case "--query":
                guard args.count == 1 else { return .failure(CommandError("--query: expected bar, defaults, events, displays or an item name")) }
                return .success(.query(args[0]))
            case "--update":
                return .success(.update)
            case "--reload":
                return .success(.reload(path: args.first))
            case "--hotload":
                guard args.count == 1, let on = Value.bool(args[0], current: false) else {
                    return .failure(CommandError("--hotload: expected on or off"))
                }
                return .success(.hotload(on))
            case "--settings":
                return .success(.settings)
            case "--exit":
                return .success(.exit)
            default:
                return .failure(CommandError("unknown command '\(name)'"))
        }
    }

    static func props(_ words: [String], _ command: String) -> Result<[Prop], CommandError> {
        var props: [Prop] = []
        for word in words {
            guard let equal = word.firstIndex(of: "="), equal != word.startIndex else {
                return .failure(CommandError("\(command): '\(word)' is not a property=value"))
            }
            props.append(Prop(String(word[..<equal]), String(word[word.index(after: equal)...])))
        }
        return .success(props)
    }
}
