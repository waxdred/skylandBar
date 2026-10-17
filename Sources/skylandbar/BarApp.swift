import AppKit
import SkylandBarCore

/// The running bar: the model the commands change, one window per display and one per open
/// popup, the system events, the timers, the scripts and the config.
final class BarApp {
    let model = BarModel()
    private let configPath: String?
    private let scripts: ScriptRunner
    private let events = SystemEvents()
    private let aliases = AliasCapture()
    private var server: Server!
    private var windows: [BarWindow] = []
    /// open popups, by the item they belong to
    private var popups: [String: BarWindow] = [:]
    private var timers: [String: Timer] = [:]
    private var aliasTimer: Timer?
    private var frameTimer: Timer?
    private var scrollTimer: Timer?
    private var layoutPending = false
    private var hotload: DispatchSourceFileSystemObject?
    private var hotloadOn = false
    private var signalSources: [DispatchSourceSignal] = []
    /// the windows (bar and popups) the mouse is in, for mouse.entered/exited.global
    private var mouseIn = Set<ObjectIdentifier>()
    private var lastSlideScript = 0.0

    init(configPath: String?) {
        self.configPath = configPath
        scripts = ScriptRunner(configDir: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func start() {
        server = Server { [unowned self] arguments in self.handle(arguments) }
        guard server.start() else {
            FileHandle.standardError.write(Data("skylandbar: cannot listen on \(Socket.path)\n".utf8))
            exit(1)
        }
        events.onEvent = { [unowned self] event, info in
            if event == "space_change" { return self.spaceChanged() }
            self.scripts.run(self.model.scripts(for: event, info: info))
        }
        events.onArtwork = { [unowned self] image in
            Images.artwork = image
            self.setNeedsLayout()
        }
        events.start()
        aliases.onChange = { [unowned self] in self.setNeedsLayout() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [unowned self] _ in
            self.rebuildWindows()
            self.model.currentSpaces = Spaces.current()
            self.scripts.run(self.model.scripts(for: "display_change"))
        }
        for signal in [SIGTERM, SIGINT] {
            Darwin.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { [unowned self] in self.quit() }
            source.resume()
            signalSources.append(source)
        }
        model.currentSpaces = Spaces.current()
        rebuildWindows()
        runConfig()
    }

    func quit() {
        server.stop()
        scripts.terminateAll()
        for window in windows + popups.values { window.panel.orderOut(nil) }
        exit(0)
    }

    // MARK: messages

    func handle(_ arguments: [String]) -> (ok: Bool, text: String) {
        switch CommandParser.parse(arguments) {
            case .failure(let error):
                return (false, "[!] \(error.message)\n")
            case .success(let commands):
                model.displays = displaysJSON()
                let queries = commands.compactMap { command -> String? in
                    if case .query(let what) = command { return what } else { return nil }
                }
                if !queries.isEmpty { layoutNow() }
                if queries.contains("default_menu_items") { model.menuItems = MenuItems.list().map(\.alias) }
                let outcome = model.execute(commands)
                apply(outcome)
                let errors = outcome.errors.map { $0 + "\n" }.joined()
                return (outcome.errors.isEmpty, outcome.output + errors)
        }
    }

    private func apply(_ outcome: Outcome) {
        if outcome.exit { return quit() }
        if outcome.reload { return reload(outcome.reloadPath) }
        if let on = outcome.hotload { setHotload(on) }
        if outcome.barChanged { configureWindows() }
        if outcome.eventsChanged { events.observeCustom(model.events) }
        if outcome.timersChanged { updateTimers() }
        if outcome.animating { startFrames() }
        if outcome.redraw || outcome.barChanged { setNeedsLayout() }
        scripts.run(outcome.scripts)
    }

    private func spaceChanged() {
        model.currentSpaces = Spaces.current()
        setNeedsLayout() // `display=active` and `space=` items follow
        scripts.run(model.spaceChange())
    }

    // MARK: config

    private var configFile: String? {
        if let configPath { return configPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.config/skylandbar/skylandbarrc", "\(home)/.config/sketchybar/sketchybarrc"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Runs the config, then every script once (`forced`), like sketchybar.
    private func runConfig() {
        guard let file = configFile else {
            FileHandle.standardError.write(Data("skylandbar: no config (~/.config/skylandbar/skylandbarrc or ~/.config/sketchybar/sketchybarrc)\n".utf8))
            setNeedsLayout()
            return
        }
        run(file)
        if hotloadOn { watch(file) }
    }

    private func run(_ file: String) {
        scripts.configDir = (file as NSString).deletingLastPathComponent
        scripts.launch(file: file) { [weak self] in
            guard let self else { return }
            self.scripts.run(self.model.scripts(for: "forced"))
            self.scripts.run(self.model.spaceChange().filter { run in self.model.item(named: run.item)?.kind == "space" })
            self.setNeedsLayout()
        }
    }

    private func reload(_ path: String?) {
        for timer in timers.values { timer.invalidate() }
        timers = [:]
        model.reset()
        events.observeCustom([:])
        updateTimers()
        configureWindows()
        if let path, FileManager.default.fileExists(atPath: path) { run(path) } else { runConfig() }
    }

    /// --hotload on: the config runs again when its file changes.
    private func setHotload(_ on: Bool) {
        hotloadOn = on
        hotload?.cancel()
        hotload = nil
        if on, let file = configFile { watch(file) }
    }

    private func watch(_ file: String) {
        hotload?.cancel()
        let fd = open(file, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            // editors replace the file: wait for it, then reload (which watches the new one)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.reload(nil) }
            source.cancel()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        hotload = source
    }

    // MARK: timers

    /// One timer per item with update_freq, sending it `routine`; one for the aliases.
    private func updateTimers() {
        for timer in timers.values { timer.invalidate() }
        timers = [:]
        for item in model.items where item.props.updateFreq > 0 && !item.props.script.isEmpty && item.props.updates != "off" {
            let name = item.name
            let timer = Timer(timeInterval: item.props.updateFreq, repeats: true) { [unowned self] _ in
                if self.model.item(named: name)?.props.updates == "when_shown" && self.model.bar.hidden == "on" { return }
                self.scripts.run(self.model.scripts(for: "routine", only: name))
            }
            timer.tolerance = min(1, item.props.updateFreq / 10)
            RunLoop.main.add(timer, forMode: .common)
            timers[name] = timer
        }
        aliasTimer?.invalidate()
        aliasTimer = nil
        let names = model.items.filter { $0.kind == "alias" }.map(\.name)
        aliases.forget(except: names)
        guard !names.isEmpty else { return }
        aliases.refresh(names)
        let every = model.items.filter { $0.kind == "alias" }.map(\.props.alias.updateFreq).min() ?? 1
        let timer = Timer(timeInterval: every, repeats: true) { [unowned self] _ in
            guard self.model.bar.hidden != "on" else { return }
            self.aliases.refresh(self.model.items.filter { $0.kind == "alias" }.map(\.name))
        }
        timer.tolerance = every / 5
        RunLoop.main.add(timer, forMode: .common)
        aliasTimer = timer
    }

    /// Frames at 60 Hz while something animates.
    private func startFrames() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [unowned self] _ in
            if self.model.isBarAnimating { self.configureWindows(layout: false) }
            self.layoutNow()
            self.model.endFinishedAnimations()
            if !self.model.isAnimating {
                self.layoutNow() // the last frame, at the targets
                self.frameTimer?.invalidate()
                self.frameTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    /// Redraws while texts scroll (`scroll_texts`).
    private func updateScrolling() {
        let scrolling = (windows + popups.values).filter { $0.view.scrolls }
        if scrolling.isEmpty {
            scrollTimer?.invalidate()
            scrollTimer = nil
        } else if scrollTimer == nil {
            let timer = Timer(timeInterval: 1 / 20, repeats: true) { [unowned self] _ in
                for window in self.windows + self.popups.values where window.view.scrolls { window.view.needsDisplay = true }
            }
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        }
    }

    // MARK: windows and layout

    /// 1-based in NSScreen order (1 = the main display), the one with the mouse.
    private var activeDisplay: Int {
        let mouse = NSEvent.mouseLocation
        return (NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0) + 1
    }

    private func rebuildWindows() {
        for window in windows { window.panel.orderOut(nil) }
        windows = []
        configureWindows()
    }

    /// A window for each display the bar is on, at its place, shown or hidden.
    private func configureWindows(layout: Bool = true) {
        let screens = NSScreen.screens
        let bar = model.displayedBar
        let wanted = screens.indices.map { $0 + 1 }.filter { bar.isShown(onDisplay: $0) }
        for window in windows where !wanted.contains(window.display) { window.panel.orderOut(nil) }
        windows = wanted.map { display in
            let window = windows.first { $0.display == display } ?? makeWindow(display)
            window.configure(bar, screen: screens[display - 1])
            return window
        }
        let active = activeDisplay
        for window in windows {
            let hidden = bar.hidden == "on" || (bar.hidden == "current" && window.display == active)
            if hidden { window.panel.orderOut(nil) } else { window.panel.orderFrontRegardless() }
        }
        if layout { setNeedsLayout() }
    }

    private func makeWindow(_ display: Int) -> BarWindow {
        let window = BarWindow(display: display)
        let view = window.view, id = ObjectIdentifier(window)
        view.onItemEntered = { [unowned self] name in self.scripts.run(self.model.scripts(for: "mouse.entered", only: name)) }
        view.onItemExited = { [unowned self] name in self.scripts.run(self.model.scripts(for: "mouse.exited", only: name)) }
        // global: entering the first of the bar's windows, leaving the last one (going
        // from the bar to its popup is neither)
        view.onBarEntered = { [unowned self] in
            if self.mouseIn.isEmpty { self.scripts.run(self.model.scripts(for: "mouse.entered.global")) }
            self.mouseIn.insert(id)
        }
        view.onBarExited = { [unowned self] in
            self.mouseIn.remove(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if self.mouseIn.isEmpty { self.scripts.run(self.model.scripts(for: "mouse.exited.global")) }
            }
        }
        view.onClick = { [unowned self] name, button, modifier in
            if let item = self.model.item(named: name), item.kind == "alias", item.props.clickScript.isEmpty,
               !item.subscriptions.contains("mouse.clicked")
            {
                return self.clickThrough(name)
            }
            self.scripts.run(self.model.click(name, button: button, modifier: modifier))
        }
        view.onScroll = { [unowned self] name, delta, modifier in
            let env = ["SCROLL_DELTA": String(Int(delta.rounded())), "MODIFIER": modifier]
            if let name { self.scripts.run(self.model.scripts(for: "mouse.scrolled", env: env, only: name)) }
            self.scripts.run(self.model.scripts(for: "mouse.scrolled.global", env: env))
        }
        view.onSlide = { [unowned self] name, percentage, modifier, done in
            let runs = self.model.slide(name, to: percentage, button: "left", modifier: modifier)
            self.setNeedsLayout()
            // while dragging, the script at most ten times a second
            let now = ProcessInfo.processInfo.systemUptime
            if done || now - self.lastSlideScript > 0.1 {
                self.lastSlideScript = now
                self.scripts.run(runs)
            }
        }
        return window
    }

    /// An alias with nothing of its own to do on a click: the real menu bar item gets it.
    /// The bar lets clicks through meanwhile, in case it covers the menu bar.
    private func clickThrough(_ alias: String) {
        let all = windows + popups.values
        for window in all { window.panel.ignoresMouseEvents = true }
        MenuItems.click(alias)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            for window in all { window.panel.ignoresMouseEvents = false }
        }
    }

    /// Lays out and redraws once, after the current burst of messages.
    private func setNeedsLayout() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in self?.layoutNow() }
    }

    /// The middle part of an item: a graph, a slider, an alias.
    private func middle(_ item: BarItem, _ props: ItemProps) -> Double {
        Layout.middle(of: item, aliasWidth: aliases.width(item.name) * props.alias.scale)
    }

    private func placed(_ item: BarItem, _ props: ItemProps, x: Double, length: Double, top: Double, height: Double, middle: Double) -> PlacedItem {
        PlacedItem(name: item.name, kind: item.kind, x: x, length: length, top: top, height: height, props: props,
                   middle: middle, graphValues: item.graphValues, alias: aliases.images[item.name])
    }

    private func layoutNow() {
        layoutPending = false
        let active = activeDisplay
        let bar = model.displayedBar
        var frames: [String: [String: Box]] = [:]
        /// where items are on screen (AppKit coordinates), for the popups under them
        var anchors: [String: (rect: NSRect, display: Int)] = [:]
        for window in windows {
            let frame = window.panel.frame
            let width = Double(frame.width), height = Double(frame.height)
            let spaces = model.currentSpaces[window.display].map { [$0] } ?? []
            let shown = model.items.filter { item in
                item.kind != "bracket" && item.props.drawing && itemPositions.contains(item.props.position)
                    && item.props.isShown(onDisplay: window.display, activeDisplay: active)
                    && (item.kind == "space" || item.props.isShown(onSpaces: spaces))
            }
            let props = shown.map { model.displayed($0) }
            let middles = zip(shown, props).map { middle($0, $1) }
            let lengths = zip(props, middles).map { Layout.length(of: $0, middle: $1, measure: Fonts.width, image: Images.width) }
            let slots = shown.indices.map { index in
                Layout.Slot(name: shown[index].name, position: props[index].position, length: lengths[index],
                            paddingLeft: props[index].background.paddingLeft, paddingRight: props[index].background.paddingRight)
            }
            let xs = Layout.place(slots, width: width, paddingLeft: bar.paddingLeft, paddingRight: bar.paddingRight,
                                  notchWidth: bar.notchWidth, notchOffset: bar.notchOffset)
            var items: [PlacedItem] = []
            for index in shown.indices {
                guard let x = xs[shown[index].name] else { continue }
                items.append(placed(shown[index], props[index], x: x, length: lengths[index], top: 0, height: height, middle: middles[index]))
                frames[shown[index].name, default: [:]]["display-\(window.display)"] = Box(x: x, y: 0, width: lengths[index], height: height)
                anchors[shown[index].name] = (NSRect(x: frame.minX + x, y: frame.minY, width: lengths[index], height: frame.height), window.display)
            }
            window.view.items = brackets(around: items, height: height) + items
            window.view.style = PanelStyle(bar: bar)
            window.view.needsDisplay = true
            window.updateGlass()
        }
        layoutPopups(bar: bar, anchors: &anchors, frames: &frames)
        model.frames = frames
        updateScrolling()
    }

    /// Each bracket around its members on this bar, behind them.
    private func brackets(around items: [PlacedItem], height: Double) -> [PlacedItem] {
        model.items.filter { $0.kind == "bracket" && $0.props.drawing }.compactMap { bracket in
            let members = Set(model.members(of: bracket))
            let inside = items.filter { members.contains($0.name) }
            guard let start = inside.map(\.x).min(), let end = inside.map({ $0.x + $0.length }).max() else { return nil }
            return placed(bracket, model.displayed(bracket), x: start, length: end - start, top: 0, height: height, middle: 0)
        }
    }

    /// The open popups: under their item (over it with a bottom bar), popups of popup items
    /// under those, a few levels deep.
    private func layoutPopups(bar: BarProps, anchors: inout [String: (rect: NSRect, display: Int)], frames: inout [String: [String: Box]]) {
        var open = Set<String>()
        if bar.hidden != "on" {
            for _ in 0 ..< 4 {
                var opened = false
                for parent in model.items where !open.contains(parent.name) && parent.props.popup.drawing {
                    guard let anchor = anchors[parent.name] else { continue }
                    let children = model.popupItems(of: parent.name).filter { $0.props.drawing }
                    guard !children.isEmpty else { continue }
                    open.insert(parent.name)
                    opened = true
                    layoutPopup(parent, children, bar: bar, anchor: anchor, anchors: &anchors, frames: &frames)
                }
                if !opened { break }
            }
        }
        for (name, window) in popups where !open.contains(name) {
            window.panel.orderOut(nil)
            mouseIn.remove(ObjectIdentifier(window))
            popups[name] = nil
        }
    }

    private func layoutPopup(_ parent: BarItem, _ children: [BarItem], bar: BarProps, anchor: (rect: NSRect, display: Int),
                             anchors: inout [String: (rect: NSRect, display: Int)], frames: inout [String: [String: Box]])
    {
        let popup = model.displayed(parent).popup
        let row = popup.height > 0 ? popup.height : bar.height
        let props = children.map { model.displayed($0) }
        let middles = zip(children, props).map { middle($0, $1) }
        let lengths = zip(props, middles).map { Layout.length(of: $0, middle: $1, measure: Fonts.width, image: Images.width) }
        let slots = children.indices.map { index in
            Layout.Slot(name: children[index].name, position: "popup", length: lengths[index],
                        paddingLeft: props[index].background.paddingLeft, paddingRight: props[index].background.paddingRight)
        }
        let laid = Layout.popup(slots, horizontal: popup.horizontal, rowHeight: row, inset: popup.background.drawing ? popup.background.borderWidth : 0)
        let x = Layout.popupX(align: popup.align, itemX: Double(anchor.rect.minX), itemLength: Double(anchor.rect.width), width: laid.width)
        let y = bar.position == "bottom" ? Double(anchor.rect.maxY) + popup.yOffset : Double(anchor.rect.minY) - popup.yOffset - laid.height
        let frame = NSRect(x: x, y: y, width: laid.width, height: laid.height)
        let window = popups[parent.name] ?? makeWindow(anchor.display)
        popups[parent.name] = window
        window.configurePopup(popup, frame: frame, bar: bar)
        var items: [PlacedItem] = []
        for index in children.indices {
            guard let place = laid.places[children[index].name] else { continue }
            items.append(placed(children[index], props[index], x: place.x, length: lengths[index], top: place.y, height: row, middle: middles[index]))
            frames[children[index].name, default: [:]]["popup.\(parent.name)"] = Box(x: place.x, y: place.y, width: lengths[index], height: row)
            anchors[children[index].name] = (NSRect(x: x + place.x, y: y + laid.height - place.y - row, width: lengths[index], height: row), anchor.display)
        }
        window.view.items = items
        window.view.needsDisplay = true
        window.updateGlass()
        window.panel.orderFrontRegardless()
    }

    private func displaysJSON() -> [[String: Any]] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
            let frame = screen.frame
            return [
                "arrangement-id": index + 1, "DirectDisplayID": id,
                "frame": ["x": frame.minX, "y": frame.minY, "w": frame.width, "h": frame.height],
            ]
        }
    }
}
