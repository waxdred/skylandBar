import Foundation

public struct BarItem: Equatable {
    public var name: String
    /// item, bracket, graph, slider, alias, space
    public var kind: String
    public var props: ItemProps
    /// the events its script gets, in subscription order
    public var subscriptions: [String] = []
    /// bracket members, graph width... as given to --add
    public var args: [String] = []
}

/// A script to run: the item's `script` (or `click_script`) with NAME, SENDER, INFO...
public struct ScriptRun: Equatable {
    public let item: String
    public let script: String
    public let env: [String: String]
}

/// What a message did, for the app to carry out.
public struct Outcome: Equatable {
    public var output = ""
    public var errors: [String] = []
    public var scripts: [ScriptRun] = []
    /// items or the bar look changed
    public var redraw = false
    /// bar windows: frame, level, displays
    public var barChanged = false
    public var timersChanged = false
    /// custom events (their distributed notifications)
    public var eventsChanged = false
    public var reload = false
    public var reloadPath: String? = nil
    public var hotload: Bool? = nil
    public var exit = false
}

/// sketchybar's built-in events
public let builtinEvents = [
    "front_app_switched", "space_change", "space_windows_change", "display_change", "volume_change",
    "brightness_change", "power_source_change", "wifi_change", "media_change", "system_will_sleep", "system_woke",
    "mouse.entered", "mouse.exited", "mouse.entered.global", "mouse.exited.global", "mouse.clicked",
    "mouse.scrolled", "mouse.scrolled.global", "forced", "routine",
]

/// The bar and its items, changed by commands. No AppKit: the app lays it out and draws it.
public final class BarModel {
    public private(set) var bar = BarProps()
    public private(set) var items: [BarItem] = []
    public private(set) var defaults = ItemProps()
    /// custom events and their NSDistributedNotification name ("" none)
    public private(set) var events: [String: String] = [:]
    /// filled by the app before a query: item name -> display key ("display-1") -> rect
    public var frames: [String: [String: Box]] = [:]
    /// filled by the app before a query
    public var displays: [[String: Any]] = []

    public init() {}

    /// Back to nothing, before the config runs again.
    public func reset() {
        bar = BarProps()
        items = []
        defaults = ItemProps()
        events = [:]
        frames = [:]
    }

    public func item(named name: String) -> BarItem? { items.first { $0.name == name } }

    /// The items `target` names: a name, or a /regex/ matched against the names.
    public func indices(matching target: String) -> [Int] {
        if target.count > 2, target.hasPrefix("/"), target.hasSuffix("/") {
            guard let regex = try? NSRegularExpression(pattern: String(target.dropFirst().dropLast())) else { return [] }
            return items.indices.filter { index in
                let name = items[index].name
                return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            }
        }
        return items.indices.filter { items[$0].name == target }
    }

    public func execute(_ commands: [Command]) -> Outcome {
        var outcome = Outcome()
        for command in commands { execute(command, &outcome) }
        return outcome
    }

    private func execute(_ command: Command, _ o: inout Outcome) {
        switch command {
            case .bar(let props):
                for prop in props {
                    if let error = bar.apply(prop.key, prop.value) { o.errors.append("[!] Bar: \(prop.key)=\(prop.value): \(error)") }
                }
                o.barChanged = true
                o.redraw = true
            case .add(let kind, let name, let args):
                add(kind, name, args, &o)
            case .set(let target, let props):
                let matches = indices(matching: target)
                if matches.isEmpty { return o.errors.append("[!] Set: no item '\(target)'") }
                for index in matches {
                    for prop in props {
                        if let error = items[index].props.apply(prop.key, prop.value) {
                            o.errors.append("[!] Set \(items[index].name): \(prop.key)=\(prop.value): \(error)")
                        }
                        if ["update_freq", "updates", "script"].contains(prop.key) { o.timersChanged = true }
                    }
                }
                o.redraw = true
            case .defaults(let props):
                for prop in props {
                    if let error = defaults.apply(prop.key, prop.value) { o.errors.append("[!] Default: \(prop.key)=\(prop.value): \(error)") }
                }
            case .subscribe(let target, let names):
                let matches = indices(matching: target)
                if matches.isEmpty { return o.errors.append("[!] Subscribe: no item '\(target)'") }
                for name in names where !builtinEvents.contains(name) && events[name] == nil {
                    o.errors.append("[!] Subscribe: no event '\(name)' (--add event \(name))")
                }
                for index in matches {
                    for name in names where !items[index].subscriptions.contains(name) { items[index].subscriptions.append(name) }
                }
                o.eventsChanged = true
            case .trigger(let event, let env):
                var vars: [String: String] = [:]
                for prop in env { vars[prop.key] = prop.value }
                o.scripts += scripts(for: event, info: vars["INFO"] ?? "", env: vars)
            case .remove(let target):
                let matches = Set(indices(matching: target))
                if matches.isEmpty { return o.errors.append("[!] Remove: no item '\(target)'") }
                items = items.enumerated().filter { !matches.contains($0.offset) }.map(\.element)
                o.redraw = true
                o.timersChanged = true
            case .move(let name, let before, let reference):
                guard let from = items.firstIndex(where: { $0.name == name }) else { return o.errors.append("[!] Move: no item '\(name)'") }
                let item = items.remove(at: from)
                guard let to = items.firstIndex(where: { $0.name == reference }) else {
                    items.insert(item, at: from)
                    return o.errors.append("[!] Move: no item '\(reference)'")
                }
                items.insert(item, at: before ? to : to + 1)
                o.redraw = true
            case .reorder(let names):
                let slots = names.compactMap { name in items.firstIndex { $0.name == name } }
                let moved = slots.map { items[$0] }
                for (slot, item) in zip(slots.sorted(), moved) { items[slot] = item }
                if slots.count < names.count { o.errors.append("[!] Reorder: some items do not exist") }
                o.redraw = true
            case .rename(let from, let to):
                guard let index = items.firstIndex(where: { $0.name == from }) else { return o.errors.append("[!] Rename: no item '\(from)'") }
                guard item(named: to) == nil else { return o.errors.append("[!] Rename: '\(to)' already exists") }
                items[index].name = to
                o.timersChanged = true
            case .clone(let name, let parent, let placement):
                guard let index = items.firstIndex(where: { $0.name == parent }) else { return o.errors.append("[!] Clone: no item '\(parent)'") }
                guard item(named: name) == nil else { return o.errors.append("[!] Clone: '\(name)' already exists") }
                var clone = items[index]
                clone.name = name
                items.insert(clone, at: placement == "before" ? index : index + 1)
                o.redraw = true
                o.timersChanged = true
            case .push(let name, let values):
                // graphs are drawn from milestone 2: their values are kept
                guard let index = items.firstIndex(where: { $0.name == name }) else { return o.errors.append("[!] Push: no item '\(name)'") }
                items[index].args += values
            case .animate:
                break // milestone 2: the following changes apply at once
            case .query(let what):
                query(what, &o)
            case .update:
                o.scripts += scripts(for: "forced")
                o.redraw = true
            case .reload(let path):
                o.reload = true
                o.reloadPath = path
            case .hotload(let on):
                o.hotload = on
            case .exit:
                o.exit = true
        }
    }

    private func add(_ kind: String, _ name: String, _ args: [String], _ o: inout Outcome) {
        if kind == "event" {
            events[name] = args.first ?? ""
            o.eventsChanged = true
            return
        }
        guard item(named: name) == nil else { return o.errors.append("[!] Add \(kind): '\(name)' already exists") }
        var props = defaults
        switch kind {
            case "item", "alias", "space", "graph", "slider":
                let position = args[0]
                guard itemPositions.contains(position) || position.hasPrefix("popup.") else {
                    return o.errors.append("[!] Add \(kind): '\(position)' is not one of \(itemPositions.joined(separator: ", ")) or popup.<item>")
                }
                props.position = position
                if kind == "graph" || kind == "slider", let width = Double(args[1]) { props.width = width }
            default: // bracket: drawn from milestone 2
                props.position = "bracket"
        }
        items.append(BarItem(name: name, kind: kind, props: props, args: kind == "bracket" ? args : []))
        o.redraw = true
    }

    /// The scripts an event runs: `forced` runs every item's script, `routine` the item's
    /// (`only`), any other event the subscribed items'. `updates=off` items run nothing.
    public func scripts(for event: String, info: String = "", env: [String: String] = [:], only: String? = nil) -> [ScriptRun] {
        items.compactMap { item in
            if let only, item.name != only { return nil }
            guard !item.props.script.isEmpty, item.props.updates != "off" else { return nil }
            if event != "forced" && event != "routine" && !item.subscriptions.contains(event) { return nil }
            var vars = env
            vars["NAME"] = item.name
            vars["SENDER"] = event
            vars["INFO"] = info
            return ScriptRun(item: item.name, script: item.props.script, env: vars)
        }
    }

    /// A click: the item's click_script, and its script when it is subscribed to mouse.clicked.
    public func click(_ name: String, button: String, modifier: String) -> [ScriptRun] {
        guard let item = item(named: name) else { return [] }
        let env = ["BUTTON": button, "MODIFIER": modifier]
        var runs: [ScriptRun] = []
        if !item.props.clickScript.isEmpty {
            runs.append(ScriptRun(item: name, script: item.props.clickScript,
                                  env: env.merging(["NAME": name, "SENDER": "mouse.clicked", "INFO": ""]) { a, _ in a }))
        }
        return runs + scripts(for: "mouse.clicked", env: env, only: name)
    }

    // MARK: queries

    private func query(_ what: String, _ o: inout Outcome) {
        let json: Any
        switch what {
            case "bar":
                var bar = self.bar.json
                bar["items"] = items.map(\.name)
                json = bar
            case "defaults":
                json = itemJSON(BarItem(name: "defaults", kind: "item", props: defaults))
            case "events":
                var all: [String: Any] = [:]
                for (index, name) in builtinEvents.enumerated() { all[name] = ["bit": index, "notification": ""] }
                for (offset, entry) in events.sorted(by: { $0.key < $1.key }).enumerated() {
                    all[entry.key] = ["bit": builtinEvents.count + offset, "notification": entry.value]
                }
                json = all
            case "displays":
                json = displays
            default:
                guard let item = item(named: what) else {
                    return o.errors.append("[!] Query: '\(what)' is not bar, defaults, events, displays or an item")
                }
                json = itemJSON(item)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return o.errors.append("[!] Query: cannot write JSON") }
        o.output += text + "\n"
    }

    private func itemJSON(_ item: BarItem) -> [String: Any] {
        var rects: [String: Any] = [:]
        for (display, box) in frames[item.name] ?? [:] {
            rects[display] = ["origin": [box.x, box.y], "size": [box.width, box.height]]
        }
        return [
            "name": item.name, "type": item.kind,
            "geometry": item.props.json,
            "icon": item.props.icon.json,
            "label": item.props.label.json,
            "scripting": [
                "script": item.props.script, "click_script": item.props.clickScript,
                "update_freq": item.props.updateFreq, "updates": item.props.updates,
                "subscriptions": item.subscriptions,
            ] as [String: Any],
            "bounding_rects": rects,
        ]
    }
}
