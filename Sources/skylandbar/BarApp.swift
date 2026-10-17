import AppKit
import SkylandBarCore

/// The running bar: the model the commands change, one window per display, the system
/// events, the update timers, the scripts and the config.
final class BarApp {
    let model = BarModel()
    private let configPath: String?
    private let scripts: ScriptRunner
    private let events = SystemEvents()
    private var server: Server!
    private var windows: [BarWindow] = []
    private var timers: [String: Timer] = [:]
    private var layoutPending = false
    private var hotload: DispatchSourceFileSystemObject?
    private var hotloadOn = false

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
            if event == "space_change" { self.setNeedsLayout() } // `display=active` items follow the focus
            self.scripts.run(self.model.scripts(for: event, info: info))
        }
        events.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [unowned self] _ in
            self.rebuildWindows()
            self.scripts.run(self.model.scripts(for: "display_change"))
        }
        for signal in [SIGTERM, SIGINT] {
            Darwin.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { [unowned self] in self.quit() }
            source.resume()
            signalSources.append(source)
        }
        rebuildWindows()
        runConfig()
    }

    private var signalSources: [DispatchSourceSignal] = []

    func quit() {
        server.stop()
        for window in windows { window.panel.orderOut(nil) }
        exit(0)
    }

    // MARK: messages

    func handle(_ arguments: [String]) -> (ok: Bool, text: String) {
        switch CommandParser.parse(arguments) {
            case .failure(let error):
                return (false, "[!] \(error.message)\n")
            case .success(let commands):
                model.displays = displaysJSON()
                if commands.contains(where: { if case .query = $0 { return true } else { return false } }) { layoutNow() }
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
        if outcome.redraw || outcome.barChanged { setNeedsLayout() }
        scripts.run(outcome.scripts)
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
        scripts.configDir = (file as NSString).deletingLastPathComponent
        scripts.launch(file: file) { [weak self] in
            guard let self else { return }
            self.scripts.run(self.model.scripts(for: "forced"))
            self.setNeedsLayout()
        }
        if hotloadOn { watch(file) }
    }

    private func reload(_ path: String?) {
        for timer in timers.values { timer.invalidate() }
        timers = [:]
        model.reset()
        events.observeCustom([:])
        configureWindows()
        if let path, FileManager.default.fileExists(atPath: path) {
            scripts.configDir = (path as NSString).deletingLastPathComponent
            scripts.launch(file: path) { [weak self] in
                guard let self else { return }
                self.scripts.run(self.model.scripts(for: "forced"))
                self.setNeedsLayout()
            }
        } else {
            runConfig()
        }
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

    /// One timer per item with update_freq, sending it `routine`.
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
    private func configureWindows() {
        let screens = NSScreen.screens
        let wanted = screens.indices.map { $0 + 1 }.filter { model.bar.isShown(onDisplay: $0) }
        for window in windows where !wanted.contains(window.display) { window.panel.orderOut(nil) }
        windows = wanted.map { display in
            let window = windows.first { $0.display == display } ?? makeWindow(display)
            window.configure(model.bar, screen: screens[display - 1])
            return window
        }
        let active = activeDisplay
        for window in windows {
            let hidden = model.bar.hidden == "on" || (model.bar.hidden == "current" && window.display == active)
            if hidden { window.panel.orderOut(nil) } else { window.panel.orderFrontRegardless() }
        }
        setNeedsLayout()
    }

    private func makeWindow(_ display: Int) -> BarWindow {
        let window = BarWindow(display: display)
        let view = window.view
        view.onItemEntered = { [unowned self] name in self.scripts.run(self.model.scripts(for: "mouse.entered", only: name)) }
        view.onItemExited = { [unowned self] name in self.scripts.run(self.model.scripts(for: "mouse.exited", only: name)) }
        view.onBarEntered = { [unowned self] in self.scripts.run(self.model.scripts(for: "mouse.entered.global")) }
        view.onBarExited = { [unowned self] in self.scripts.run(self.model.scripts(for: "mouse.exited.global")) }
        view.onClick = { [unowned self] name, button, modifier in
            self.scripts.run(self.model.click(name, button: button, modifier: modifier))
        }
        view.onScroll = { [unowned self] name, delta, modifier in
            let env = ["SCROLL_DELTA": String(Int(delta.rounded())), "MODIFIER": modifier]
            if let name { self.scripts.run(self.model.scripts(for: "mouse.scrolled", env: env, only: name)) }
            self.scripts.run(self.model.scripts(for: "mouse.scrolled.global", env: env))
        }
        return window
    }

    /// Lays out and redraws once, after the current burst of messages.
    private func setNeedsLayout() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in self?.layoutNow() }
    }

    private func layoutNow() {
        layoutPending = false
        let active = activeDisplay
        var frames: [String: [String: Box]] = [:]
        for window in windows {
            let width = Double(window.panel.frame.width), height = Double(window.panel.frame.height)
            let shown = model.items.filter { item in
                item.kind != "bracket" && item.props.drawing && itemPositions.contains(item.props.position)
                    && item.props.isShown(onDisplay: window.display, activeDisplay: active)
            }
            let lengths = shown.map { Layout.length(of: $0.props, measure: Fonts.width) }
            let slots = zip(shown, lengths).map { item, length in
                Layout.Slot(name: item.name, position: item.props.position, length: length,
                            paddingLeft: item.props.background.paddingLeft, paddingRight: item.props.background.paddingRight)
            }
            let bar = model.bar
            let xs = Layout.place(slots, width: width, paddingLeft: bar.paddingLeft, paddingRight: bar.paddingRight,
                                  notchWidth: bar.notchWidth, notchOffset: bar.notchOffset)
            window.view.items = zip(shown, lengths).compactMap { item, length in
                guard let x = xs[item.name] else { return nil }
                frames[item.name, default: [:]]["display-\(window.display)"] = Box(x: x, y: 0, width: length, height: height)
                return PlacedItem(name: item.name, x: x, length: length, props: item.props)
            }
            window.view.bar = bar
            window.view.needsDisplay = true
        }
        model.frames = frames
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
