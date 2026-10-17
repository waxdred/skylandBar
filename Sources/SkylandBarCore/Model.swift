import Foundation

public struct BarItem: Equatable {
    public var name: String
    /// item, bracket, graph, slider, alias, space
    public var kind: String
    public var props: ItemProps
    /// the events its script gets, in subscription order
    public var subscriptions: [String] = []
    /// bracket members (names or /regex/), as given to --add
    public var args: [String] = []
    /// a graph's values (0...1) given with --push, the newest last
    public var graphValues: [Double] = []
}

/// A script to run: the item's `script` (or `click_script`) with NAME, SENDER, INFO...;
/// and/or the same variables sent to its `mach_helper` (SbarLua, helper programs).
public struct ScriptRun: Equatable {
    public let item: String
    public let script: String
    public let env: [String: String]
    /// the bootstrap name of the item's mach_helper, "" none
    public var helper = ""
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
    /// an --animate started: draw frames until `BarModel.isAnimating` is false
    public var animating = false
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
] + skylandEvents

/// The events skylandbar sends from skyland's (or AeroSpace's) `subscribe`, with their
/// variables. The aerospace_ names are the ones sketchybar configs for AeroSpace already use
/// (`exec-on-workspace-change`), so they work without it.
public let skylandEvents = [
    "skyland_workspace_change", // FOCUSED_WORKSPACE, PREV_WORKSPACE
    "aerospace_workspace_change", // the same
    "skyland_focus_change", // FOCUSED_WORKSPACE, WINDOW_ID
    "skyland_monitor_change", // FOCUSED_WORKSPACE, MONITOR
    "skyland_mode_change", // MODE
    "aerospace_mode_change", // the same
    "skyland_window_detected", // WINDOW_ID, WORKSPACE, APP_NAME, APP_BUNDLE_ID
    "skyland_binding", // MODE, BINDING
]

/// skyland's `subscribe` event (its JSON) as the bar's events and their variables.
public func skylandEvent(_ json: [String: Any]) -> [(event: String, env: [String: String])] {
    func text(_ key: String) -> String {
        switch json[key] {
            case let string as String: return string
            case let number as NSNumber: return number.stringValue
            default: return ""
        }
    }
    switch json["_event"] as? String {
        case "focused-workspace-changed"?:
            let env = ["FOCUSED_WORKSPACE": text("workspace"), "PREV_WORKSPACE": text("prevWorkspace")]
            return [("skyland_workspace_change", env), ("aerospace_workspace_change", env)]
        case "focus-changed"?:
            return [("skyland_focus_change", ["FOCUSED_WORKSPACE": text("workspace"), "WINDOW_ID": text("windowId")])]
        case "focused-monitor-changed"?:
            return [("skyland_monitor_change", ["FOCUSED_WORKSPACE": text("workspace"), "MONITOR": text("monitorId")])]
        case "mode-changed"?:
            let env = ["MODE": text("mode")]
            return [("skyland_mode_change", env), ("aerospace_mode_change", env)]
        case "window-detected"?:
            return [("skyland_window_detected", ["WINDOW_ID": text("windowId"), "WORKSPACE": text("workspace"),
                                                 "APP_NAME": text("appName"), "APP_BUNDLE_ID": text("appBundleId")])]
        case "binding-triggered"?:
            return [("skyland_binding", ["MODE": text("mode"), "BINDING": text("binding")])]
        default:
            return []
    }
}

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
    /// filled by the app before a query: the menu bar items an alias can copy ("Owner,Name")
    public var menuItems: [String] = []
    /// set by the app: the Mission Control space shown on each display (1-based both)
    public var currentSpaces: [Int: Int] = [:]
    /// seconds, for animations; tests set their own
    public var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    /// --animate of the message being run
    private var animation: (curve: Curve, frames: Double)?
    private var itemTransitions: [String: Transition<ItemProps>] = [:]
    private var barTransition: Transition<BarProps>?

    public init() {}

    /// Back to nothing, before the config runs again.
    public func reset() {
        bar = BarProps()
        items = []
        defaults = ItemProps()
        events = [:]
        frames = [:]
        itemTransitions = [:]
        barTransition = nil
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
        animation = nil
        for command in commands { execute(command, &outcome) }
        animation = nil
        return outcome
    }

    // MARK: animations

    public var isAnimating: Bool { !itemTransitions.isEmpty || barTransition != nil }
    public var isBarAnimating: Bool { barTransition != nil }

    /// The item as drawn now: on its way to its properties while it is animated.
    public func displayed(_ item: BarItem) -> ItemProps {
        guard let transition = itemTransitions[item.name] else { return item.props }
        return .blend(transition.from, item.props, transition.progress(at: clock()))
    }

    /// The bar as drawn now.
    public var displayedBar: BarProps {
        guard let transition = barTransition else { return bar }
        return .blend(transition.from, bar, transition.progress(at: clock()))
    }

    /// Forgets the animations that are over; call it after drawing a frame.
    public func endFinishedAnimations() {
        let now = clock()
        itemTransitions = itemTransitions.filter { !$0.value.isDone(at: now) }
        if barTransition?.isDone(at: now) == true { barTransition = nil }
    }

    private func transition<Props>(from: Props, _ animation: (curve: Curve, frames: Double)) -> Transition<Props> {
        Transition(from: from, start: clock(), duration: animation.frames / framesPerSecond, curve: animation.curve)
    }

    private func execute(_ command: Command, _ o: inout Outcome) {
        switch command {
            case .bar(let props):
                let before = displayedBar
                defer {
                    if let animation, bar != before {
                        barTransition = transition(from: before, animation)
                        o.animating = true
                    }
                }
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
                    let before = displayed(items[index])
                    defer {
                        if let animation, items[index].props != before {
                            itemTransitions[items[index].name] = transition(from: before, animation)
                            o.animating = true
                        }
                    }
                    for prop in props {
                        if let error = items[index].props.apply(prop.key, prop.value) {
                            o.errors.append("[!] Set \(items[index].name): \(prop.key)=\(prop.value): \(error)")
                        }
                        if ["update_freq", "updates", "script", "alias.update_freq"].contains(prop.key) { o.timersChanged = true }
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
                for index in matches { itemTransitions[items[index].name] = nil }
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
                itemTransitions[to] = itemTransitions.removeValue(forKey: from)
                for popup in items.indices where items[popup].props.position == "popup.\(from)" {
                    items[popup].props.position = "popup.\(to)"
                }
                o.timersChanged = true
                o.redraw = true
            case .clone(let name, let parent, let placement):
                guard let index = items.firstIndex(where: { $0.name == parent }) else { return o.errors.append("[!] Clone: no item '\(parent)'") }
                guard item(named: name) == nil else { return o.errors.append("[!] Clone: '\(name)' already exists") }
                var clone = items[index]
                clone.name = name
                items.insert(clone, at: placement == "before" ? index : index + 1)
                o.redraw = true
                o.timersChanged = true
            case .push(let name, let values):
                guard let index = items.firstIndex(where: { $0.name == name }) else { return o.errors.append("[!] Push: no item '\(name)'") }
                guard items[index].kind == "graph" else { return o.errors.append("[!] Push: '\(name)' is not a graph") }
                for value in values {
                    guard let number = Double(value), number.isFinite else {
                        o.errors.append("[!] Push \(name): '\(value)' is not a number")
                        continue
                    }
                    items[index].graphValues.append(min(1, max(0, number)))
                }
                let keep = max(1, Int(items[index].props.graph.width.rounded()))
                if items[index].graphValues.count > keep { items[index].graphValues.removeFirst(items[index].graphValues.count - keep) }
                o.redraw = true
            case .animate(let name, let frames):
                guard let curve = Curve(rawValue: name) else {
                    return o.errors.append("[!] Animate: '\(name)' is not one of \(Curve.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                animation = (curve, frames)
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
                if kind == "graph", let width = Double(args[1]) { props.graph.width = width }
                if kind == "slider", let width = Double(args[1]) { props.slider.width = width }
            default: // bracket: drawn from milestone 2
                props.position = "bracket"
        }
        items.append(BarItem(name: name, kind: kind, props: props, args: kind == "bracket" ? args : []))
        o.redraw = true
        if kind == "alias" { o.timersChanged = true }
    }

    // MARK: popups, brackets, sliders, spaces

    /// The items in `parent`'s popup, in order.
    public func popupItems(of parent: String) -> [BarItem] {
        items.filter { $0.props.position == "popup.\(parent)" }
    }

    /// A bracket's members (its names and /regex/ resolved), in bar order.
    public func members(of bracket: BarItem) -> [String] {
        let wanted = Set(bracket.args.flatMap { indices(matching: $0) })
        return items.indices.filter { wanted.contains($0) && items[$0].kind != "bracket" }.map { items[$0].name }
    }

    /// A slider moved by the mouse: its percentage, then mouse.clicked with PERCENTAGE.
    public func slide(_ name: String, to percentage: Double, button: String, modifier: String) -> [ScriptRun] {
        guard let index = items.firstIndex(where: { $0.name == name }) else { return [] }
        let percent = min(100, max(0, percentage)).rounded()
        items[index].props.slider.percentage = percent
        return click(name, button: button, modifier: modifier, env: ["PERCENTAGE": String(Int(percent))])
    }

    /// space_change: the subscribed items and every `space` item, which gets SELECTED
    /// (true when its space is shown), SID (its space) and DID (the display showing it);
    /// INFO is {"display-N": space} from `currentSpaces`.
    public func spaceChange() -> [ScriptRun] {
        let info = "{" + currentSpaces.sorted { $0.key < $1.key }.map { "\"display-\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        return items.compactMap { item in
            guard item.props.hasScript, item.props.updates != "off",
                  item.kind == "space" || item.subscriptions.contains("space_change") else { return nil }
            var env = ["NAME": item.name, "SENDER": "space_change", "INFO": info]
            if item.kind == "space" {
                let spaces = item.props.space.split(separator: ",").compactMap { Int($0) }
                let shown = currentSpaces.first { spaces.contains($0.value) }
                env["SELECTED"] = shown == nil ? "false" : "true"
                if let sid = spaces.first { env["SID"] = String(sid) }
                if let shown { env["DID"] = String(shown.key) } else if let did = Int(item.props.display) { env["DID"] = String(did) }
            }
            return ScriptRun(item: item.name, script: item.props.script, env: env, helper: item.props.machHelper)
        }
    }

    /// Whether an item listens to `event`, so the app looks things up only when needed.
    public func isSubscribed(to event: String) -> Bool {
        items.contains { $0.subscriptions.contains(event) && $0.props.hasScript }
    }

    /// The scripts an event runs: `forced` runs every item's script, `routine` the item's
    /// (`only`), any other event the subscribed items'. `updates=off` items run nothing.
    public func scripts(for event: String, info: String = "", env: [String: String] = [:], only: String? = nil) -> [ScriptRun] {
        items.compactMap { item in
            if let only, item.name != only { return nil }
            guard item.props.hasScript, item.props.updates != "off" else { return nil }
            if event != "forced" && event != "routine" && !item.subscriptions.contains(event) { return nil }
            var vars = env
            vars["NAME"] = item.name
            vars["SENDER"] = event
            vars["INFO"] = info
            return ScriptRun(item: item.name, script: item.props.script, env: vars, helper: item.props.machHelper)
        }
    }

    /// A click: the item's click_script, and its script when it is subscribed to mouse.clicked.
    public func click(_ name: String, button: String, modifier: String, env extra: [String: String] = [:]) -> [ScriptRun] {
        guard let item = item(named: name) else { return [] }
        let env = extra.merging(["BUTTON": button, "MODIFIER": modifier]) { _, b in b }
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
            case "default_menu_items":
                json = menuItems
            default:
                guard let item = item(named: what) else {
                    return o.errors.append("[!] Query: '\(what)' is not bar, defaults, events, displays, default_menu_items or an item")
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
        var json: [String: Any] = [
            "name": item.name, "type": item.kind,
            "geometry": item.props.json,
            "icon": item.props.icon.json,
            "label": item.props.label.json,
            "popup": item.props.popup.json.merging(["items": popupItems(of: item.name).map(\.name)]) { a, _ in a },
            "scripting": [
                "script": item.props.script, "click_script": item.props.clickScript, "mach_helper": item.props.machHelper,
                "update_freq": item.props.updateFreq, "updates": item.props.updates,
                "subscriptions": item.subscriptions,
            ] as [String: Any],
            "bounding_rects": rects,
        ]
        switch item.kind {
            case "bracket": json["bracket"] = members(of: item)
            case "graph": json["graph"] = item.props.graph.json.merging(["values": item.graphValues]) { a, _ in a }
            case "slider": json["slider"] = item.props.slider.json
            case "alias": json["alias"] = item.props.alias.json
            default: break
        }
        return json
    }
}
