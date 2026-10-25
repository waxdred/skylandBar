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
    private let skyland = SkylandEvents()
    private var server: Server!
    private var mach: MachServer!
    private var windows: [BarWindow] = []
    /// open popups, by the item they belong to
    private var popups: [String: BarWindow] = [:]
    private var timers: [String: Timer] = [:]
    private var aliasTimer: Timer?
    private var frameTimer: FrameTicker?
    private var scrollTimer: Timer?
    private var layoutPending = false
    private var hotload: DispatchSourceFileSystemObject?
    private var hotloadOn = false
    private var settingsWindow: SettingsWindow?
    private var signalSources: [DispatchSourceSignal] = []
    /// the windows (bar and popups) the mouse is in, for mouse.entered/exited.global
    private var mouseIn = Set<ObjectIdentifier>()
    private var lastSlideScript = 0.0
    /// the display of the focused window (`display=active`), nil: the mouse's
    private var focusedDisplay: Int?
    /// space_windows_change: the last INFO sent for each display, and the timer that looks
    private var spaceWindows: [Int: String] = [:]
    private var windowsTimer: Timer?
    /// a skyland query on its way, and whether another is wanted after it
    private var skylandAsking = false
    /// the bar's height skyland was told (`bar-height`), nil: not yet / skyland restarted
    private var skylandBarHeight: Int?
    private var skylandAskAgain = false
    private var lastWorkspaceScroll = 0.0
    /// the TOML config has [vars.dark] / [vars.light]: it loads again when the appearance changes
    private var configUsesAppearance = false
    /// the notch: its window, how open it is (0...1, animated), the hover's pending open or close
    private var notchWindow: BarWindow?
    private var notchProgress = 0.0
    private var notchMove: (from: Double, to: Double, start: Double, duration: Double, curve: Curve, spring: Spring?)?
    private var notchTicker: FrameTicker?
    private var notchHover: DispatchWorkItem?
    private var notchOpen = false
    /// the frontmost app's menus in a bracket's glass (an item's `menubar=<bracket>`), how open
    /// (0...1, a spring), the title under the mouse and the one whose menu is open
    private var menuBar: (trigger: String, bracket: String, display: Int, menus: [(title: String, menu: AXUIElement?)])?
    private var menuOpen = false
    private var menuProgress = 0.0
    private var menuMove: (from: Double, to: Double, start: Double)?
    private var menuTicker: FrameTicker?
    private var menuHovered: String?
    private var menuShown: String?
    private var menuMonitor: Any?
    private let menuBarCover = MenuBarCover()

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
        mach = MachServer { [unowned self] arguments in self.handle(arguments) }
        mach.start()
        // SbarLua finds the bar by BAR_NAME: the compatibility name when we hold it (Mach.swift)
        scripts.barName = mach.names.first { $0 == "sketchybar" } ?? "skylandbar"
        events.onEvent = { [unowned self] event, info in
            if ["space_change", "front_app_switched", "display_change", "system_woke"].contains(event) { self.behindChanged() }
            if event == "space_change" { return self.spaceChanged() }
            if event == "front_app_switched" {
                self.focusChanged()
                self.askSkyland()
            }
            self.scripts.run(self.model.scripts(for: event, info: info))
        }
        skyland.onConnect = { [unowned self] in
            self.askSkyland()
            self.skylandBarHeight = nil // a restarted skyland forgot it
            self.tellSkylandBarHeight()
        }
        skyland.onEvent = { [unowned self] event, env in
            if ["skyland_workspace_change", "skyland_focus_change", "skyland_monitor_change"].contains(event) { self.behindChanged() }
            if event == "skyland_workspace_swipe" { self.swiped(env) }
            if event != "skyland_binding" && event != "skyland_workspace_swipe" && event != "skyland_mode_change" && event != "aerospace_mode_change" {
                self.focusChanged()
                if event != "aerospace_workspace_change" { self.askSkyland() } // sent with skyland_workspace_change
            }
            self.scripts.run(self.model.scripts(for: event, info: env["INFO"] ?? "", env: env))
        }
        skyland.start()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [unowned self] _ in self.checkSpaceWindows() }
        }
        events.onArtwork = { [unowned self] image in
            Images.artwork = image
            self.setNeedsLayout()
        }
        events.start()
        // the glass's snapshot of what is behind, again now and then: a window that slid under
        // the bar, a wallpaper set by a script
        let snapshots = Timer(timeInterval: 30, repeats: true) { [unowned self] _ in self.behindChanged() }
        snapshots.tolerance = 5
        RunLoop.main.add(snapshots, forMode: .common)
        aliases.onChange = { [unowned self] in self.setNeedsLayout() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [unowned self] _ in
            self.rebuildWindows()
            self.model.currentSpaces = Spaces.current()
            self.focusChanged()
            self.scripts.run(self.model.scripts(for: "display_change"))
        }
        // a client gone before its answer (`already running` checks connect and close): a
        // failed write, not the bar's end
        Darwin.signal(SIGPIPE, SIG_IGN)
        for signal in [SIGTERM, SIGINT] {
            Darwin.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { [unowned self] in self.quit() }
            source.resume()
            signalSources.append(source)
        }
        model.currentSpaces = Spaces.current()
        fullScreenDisplays = Spaces.fullScreen() // started over a full screen app: hidden there
        focusedDisplay = Windows.focusedDisplay()
        watchAccessibilityAndAppearance()
        menuBarCover.onHide = { [unowned self] in self.configureWindows() }
        rebuildWindows()
        runConfig()
    }

    func quit() {
        if skylandBarHeight != nil { SkylandSocket.runNow(["bar-height", "default"]) } // windows back to the config's bar-height
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
                return (!outcome.failed, outcome.output + errors)
        }
    }

    private func apply(_ outcome: Outcome) {
        // a swipe sent by hand (--trigger skyland_workspace_swipe ...): as skyland's, to test the lens
        for trigger in outcome.triggered where trigger.event == "skyland_workspace_swipe" { swiped(trigger.env) }
        if outcome.exit { return quit() }
        if outcome.reload { return reload(outcome.reloadPath) }
        if let on = outcome.hotload { setHotload(on) }
        if outcome.settings { openSettings() }
        if outcome.barChanged {
            updateMotion()
            configureWindows()
            behindChanged() // a theme's wallpaper comes with its colors
        }
        if outcome.eventsChanged {
            events.observeCustom(model.events)
            watchSpaceWindows()
        }
        if outcome.timersChanged { updateTimers() }
        if outcome.animating { startFrames() }
        if outcome.componentsChanged { askSkyland() }
        if outcome.notchChanged { notchChanged() }
        if outcome.redraw || outcome.barChanged { setNeedsLayout() }
        scripts.run(outcome.scripts)
    }

    // MARK: appearance and accessibility

    /// "dark" or "light", as the system shows now.
    private static var appearance: String {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? "dark" : "light"
    }

    /// Reduce Motion ends animations at once (Liquid Glass's own effects follow Reduce
    /// Transparency and Increase Contrast by themselves). A change of appearance is the
    /// appearance_change event (INFO dark or light, APPEARANCE in scripts), and loads a TOML
    /// config with [vars.dark] / [vars.light] again.
    private func watchAccessibilityAndAppearance() {
        updateMotion()
        scripts.appearance = Self.appearance
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main)
        { [unowned self] _ in
            self.updateMotion()
            self.setNeedsLayout()
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main)
        { [unowned self] _ in
            // the setting is written just after the notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let appearance = Self.appearance
                guard appearance != self.scripts.appearance else { return }
                self.scripts.appearance = appearance
                self.scripts.run(self.model.scripts(for: "appearance_change", info: appearance))
                if self.configUsesAppearance { self.reload(nil) }
            }
        }
    }

    // MARK: skyland components

    /// Asks skyland for what the workspaces and title components show, when there are
    /// some; one query at a time, and one more when asked meanwhile.
    private func askSkyland() {
        let wantsWorkspaces = model.items.contains { $0.kind == "workspaces" }
        let wantsTitle = model.items.contains { $0.kind == "title" }
        guard wantsWorkspaces || wantsTitle else { return }
        if skylandAsking {
            skylandAskAgain = true
            return
        }
        skylandAsking = true
        let group = DispatchGroup()
        var workspaces: String?, windows: String?, focused: String?
        if wantsWorkspaces {
            group.enter()
            SkylandSocket.run(SkylandData.workspacesCommand) { workspaces = $0; group.leave() }
            group.enter()
            SkylandSocket.run(SkylandData.windowsCommand) { windows = $0; group.leave() }
        }
        if wantsTitle {
            group.enter()
            SkylandSocket.run(SkylandData.focusedCommand) { focused = $0; group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.skylandAsking = false
            if let workspaces, let windows, self.model.setWorkspaces(SkylandData.workspaces(workspaces, windows: windows)) {
                self.startFrames()
            }
            // a swipe that switched: its lens goes on from where the fingers left it
            if let swipe = self.swipe, self.model.workspaces.contains(where: { $0.focused && $0.name == swipe.to }) { self.setSwipe(nil) }
            if wantsTitle { self.model.setFocusedWindow(focused.flatMap(SkylandData.focusedWindow)) }
            self.setNeedsLayout()
            if self.skylandAskAgain {
                self.skylandAskAgain = false
                self.askSkyland()
            }
        }
    }

    // MARK: workspace swipe

    /// skyland's swipe in progress: the workspace items' lens goes with the fingers
    private var swipe: (from: String, to: String)?

    private func swiped(_ env: [String: String]) {
        let from = env["FOCUSED_WORKSPACE"] ?? "", to = env["TARGET_WORKSPACE"] ?? ""
        // fingers lifted: a switch clears it once skyland's new focus is in (askSkyland), else now
        if to.isEmpty { return setSwipe(nil) }
        swipe = (from, to)
        setSwipe(BarWindow.Swipe(from: workspaceItems(from), to: workspaceItems(to), progress: Double(env["PROGRESS"] ?? "") ?? 0))
    }

    private func workspaceItems(_ workspace: String) -> Set<String> {
        Set(model.items.filter { $0.kind == "workspace" && $0.workspace == workspace }.map(\.name))
    }

    private func setSwipe(_ value: BarWindow.Swipe?) {
        if value == nil { swipe = nil }
        for window in windows { window.swipe = value }
    }

    /// What is behind the bar may have changed: the glass takes a new snapshot of it, after
    /// the change is on screen (a workspace's windows, a wallpaper fading in).
    private func behindChanged() {
        behindWork?.cancel()
        let work = DispatchWorkItem { NotificationCenter.default.post(name: BackdropCapture.behindChanged, object: nil) }
        behindWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private var behindWork: DispatchWorkItem?

    /// displays showing a full screen app (Spaces.fullScreen): no bar there
    private var fullScreenDisplays: Set<Int> = []

    private func spaceChanged() {
        model.currentSpaces = Spaces.current()
        // a full screen app or video: its display's bar goes, as the menu bar does (above
        // every Space, the bar's level showed over it)
        let full = Spaces.fullScreen()
        if full != fullScreenDisplays {
            fullScreenDisplays = full
            configureWindows()
        }
        setNeedsLayout() // `space=` items follow
        scripts.run(model.spaceChange())
        focusChanged()
    }

    /// Another window has the focus: `display=active` items and `hidden=current` follow
    /// its display. Looked up again a moment later, for a window still opening. A burst of
    /// events (a workspace switch sends 3 or 4) looks once, and once again after the last:
    /// each looked up every window on screen.
    private func focusChanged() {
        focusWork?.cancel()
        if !focusPending {
            focusPending = true
            DispatchQueue.main.async { [weak self] in
                self?.focusPending = false
                self?.lookUpFocus()
            }
        }
        let again = DispatchWorkItem { [weak self] in self?.lookUpFocus() }
        focusWork = again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: again)
    }

    private var focusPending = false
    private var focusWork: DispatchWorkItem?

    private func lookUpFocus() {
        let display = Windows.focusedDisplay()
        if display != nil && display != focusedDisplay {
            focusedDisplay = display
            if model.bar.hidden == "current" { configureWindows() } else { setNeedsLayout() }
        }
        checkSpaceWindows()
    }

    // MARK: space_windows_change

    /// While an item listens to it, the windows are looked at every 2 seconds too (closing
    /// a window says nothing to the bar).
    private func watchSpaceWindows() {
        let wanted = model.isSubscribed(to: "space_windows_change")
        if !wanted {
            windowsTimer?.invalidate()
            windowsTimer = nil
            spaceWindows = [:]
        } else if windowsTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [unowned self] _ in self.checkSpaceWindows() }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            windowsTimer = timer
            checkSpaceWindows()
        }
    }

    /// INFO {"space": N, "apps": {"App": windows}} for each display whose space shows other
    /// windows than last time.
    private func checkSpaceWindows() {
        guard windowsTimer != nil else { return }
        let apps = Windows.appsByDisplay()
        for display in NSScreen.screens.indices.map({ $0 + 1 }) {
            let space = model.currentSpaces[display] ?? display
            let json: [String: Any] = ["space": space, "apps": apps[display] ?? [:]]
            guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { continue }
            let info = String(decoding: data, as: UTF8.self)
            if spaceWindows[display] == info { continue }
            spaceWindows[display] = info
            scripts.run(model.scripts(for: "space_windows_change", info: info))
        }
    }

    // MARK: config

    private var configFile: String? {
        if let configPath { return configPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.config/skylandbar/skylandbar.toml", "\(home)/.config/skylandbar/skylandbarrc"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Runs the config, then every script once (`forced`) unless it sent `--update`.
    private func runConfig() {
        guard let file = configFile else {
            FileHandle.standardError.write(Data("skylandbar: no config (~/.config/skylandbar/skylandbar.toml or skylandbarrc)\n".utf8))
            setNeedsLayout()
            return
        }
        run(file)
        if hotloadOn { watch(file) }
    }

    /// Runs a config, then every script once when it ends, unless the config sent `--update`
    /// (its own forced run: twice would race scripts writing the same files); a
    /// config that keeps running (SbarLua's event loop) gets that after 2 seconds.
    private func run(_ file: String) {
        scripts.configDir = (file as NSString).deletingLastPathComponent
        Fonts.register(in: ["\(scripts.configDir)/fonts", "\(scripts.configDir)/themes/fonts"])
        if file.hasSuffix(".toml") { return load(file) }
        var forced = false
        let updates = model.updates
        let force = { [weak self] in
            guard let self, !forced else { return }
            forced = true
            if self.model.updates == updates { self.scripts.run(self.model.scripts(for: "forced")) }
            self.scripts.run(self.model.spaceChange().filter { run in self.model.item(named: run.item)?.kind == "space" })
            self.setNeedsLayout()
        }
        scripts.launch(file: file, onExit: force)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: force)
    }

    /// skylandbar.toml: its commands run here, at once, each part's errors reported with
    /// its place; then its `exec` commands, then every script once (`forced`).
    private func load(_ file: String) {
        let say = { (text: String) in FileHandle.standardError.write(Data("skylandbar: \(file): \(text)\n".utf8)) }
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return say("cannot read it") }
        let read = { (path: String) in try? String(contentsOfFile: path, encoding: .utf8) }
        switch ConfigFile.plan(text, environment: scripts.environment, read: read) {
            case .failure(let error):
                say(error.message)
            case .success(let plan):
                configUsesAppearance = plan.usesAppearance
                watchVarsFiles(plan.varsFiles)
                for step in plan.steps {
                    let answer = handle(step.arguments)
                    let problems = answer.text.split(separator: "\n").filter { $0.hasPrefix("[") }
                    for problem in problems { say("\(step.source): \(problem)") }
                }
                for command in plan.exec { scripts.launch(["/bin/bash", "-c", command], env: [:]) }
                scripts.run(model.scripts(for: "forced"))
                scripts.run(model.spaceChange().filter { run in model.item(named: run.item)?.kind == "space" })
        }
        setNeedsLayout()
    }

    private var varsWatch: [DispatchSourceFileSystemObject] = []

    /// A vars_file changed (skyland wrote its theme): load the config again, which watches
    /// the new file.
    private func watchVarsFiles(_ files: [String]) {
        for source in varsWatch { source.cancel() }
        varsWatch = files.compactMap { file in
            let fd = open(file, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                for source in self.varsWatch { source.cancel() }
                self.varsWatch = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.reload(nil) }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
    }

    private func reload(_ path: String?) {
        scripts.terminateAll() // the config too, when it still runs (SbarLua)
        for timer in timers.values { timer.invalidate() }
        timers = [:]
        model.reset()
        events.observeCustom([:])
        updateTimers()
        configureWindows()
        if let path, FileManager.default.fileExists(atPath: path) { run(path) } else { runConfig() }
    }

    /// --settings: the bar's settings window (Settings.swift); saved, the bar loads its config
    /// again (hotload does when it is on). Again on a shown window: it closes.
    private func openSettings() {
        guard let file = configFile else {
            return FileHandle.standardError.write(Data("skylandbar: --settings: no config file\n".utf8))
        }
        MainActor.assumeIsolated { showSettings(file) } // commands are handled on the main thread
    }

    @MainActor
    private func showSettings(_ file: String) {
        if settingsWindow == nil {
            var environment = scripts.environment
            environment["CONFIG_DIR"] = (file as NSString).deletingLastPathComponent
            let model = SettingsModel(file: file, current: { [unowned self] in
                let bar = self.model.bar.json.mapValues { "\($0)" }
                var components: [SettingField.Place: (name: String, options: [String: String])] = [:]
                if let notch = self.model.notch { components[.notch] = (notch.name, notch.options) }
                if let workspaces = self.model.items.first(where: { $0.kind == "workspaces" }) {
                    components[.workspaces] = (workspaces.name, workspaces.options)
                }
                return (bar, components)
            }, check: { text in
                guard file.hasSuffix(".toml") else { return nil }
                if case .failure(let error) = ConfigFile.plan(text, environment: environment, read: { try? String(contentsOfFile: $0, encoding: .utf8) }) {
                    return error.message
                }
                return nil
            }, reloaded: { [weak self] in
                guard let self, !self.hotloadOn else { return }
                self.reload(nil)
            })
            settingsWindow = SettingsWindow(model: model)
        }
        settingsWindow?.toggle()
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
        for item in model.items where item.props.updateFreq > 0 && item.props.hasScript && item.props.updates != "off" {
            let name = item.name
            let timer = Timer(timeInterval: item.props.updateFreq, repeats: true) { [unowned self] _ in
                // when_shown: not while the item or the bar is hidden
                if let item = self.model.item(named: name), item.props.updates == "when_shown",
                   !item.props.drawing || self.model.bar.hidden == "on" { return }
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
    /// Frames while something animates, at the display's refresh rate (120 Hz on ProMotion):
    /// only the windows whose items moved draw again.
    private func startFrames() {
        guard frameTimer == nil else { return }
        // a shown bar's display link: a hidden one's does not fire
        frameTimer = FrameTicker(view: windows.first { $0.panel.isVisible }?.view) { [unowned self] in
            if self.model.isBarAnimating { self.configureWindows(layout: false) }
            self.layoutNow()
            self.model.endFinishedAnimations()
            if !self.model.isAnimating {
                self.layoutNow() // the last frame, at the targets
                self.frameTimer?.stop()
                self.frameTimer = nil
            }
        }
    }

    /// Redraws while texts scroll (`scroll_texts`).
    private func updateScrolling() {
        let scrolling = (windows + popups.values).filter { $0.view.scrolls }
        if scrolling.isEmpty {
            scrollTimer?.invalidate()
            scrollTimer = nil
        } else if scrollTimer == nil {
            let timer = Timer(timeInterval: 1 / 20, repeats: true) { [unowned self] _ in
                for window in self.windows + self.popups.values where window.view.scrolls { window.view.redrawScrolling() }
            }
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        }
    }

    // MARK: windows and layout

    /// 1-based in NSScreen order (1 = the main display): the focused window's, else the
    /// one with the mouse.
    private var activeDisplay: Int {
        if let focusedDisplay, focusedDisplay <= NSScreen.screens.count { return focusedDisplay }
        let mouse = NSEvent.mouseLocation
        return (NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0) + 1
    }

    private func rebuildWindows() {
        for window in windows { window.panel.orderOut(nil) }
        windows = []
        configureWindows()
        if let ticker = frameTimer { // its display link was a window's that is gone
            ticker.stop()
            frameTimer = nil
            startFrames()
        }
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
            let hidden = (bar.hidden == "on" && !menuBarCover.isShown) || (bar.hidden == "current" && window.display == active)
                || fullScreenDisplays.contains(window.display)
            if hidden { window.panel.orderOut(nil) } else { window.panel.orderFrontRegardless() }
        }
        if layout { setNeedsLayout() }
        tellSkylandBarHeight()
    }

    /// skyland lays windows out below the bar: tells it the room the bar takes at the top
    /// (0 at the bottom) when it changes. Hidden keeps the room: skyland hides the bar while the
    /// macOS menu bar slides in over it, and the windows must not resize. From the bar's set properties, not the
    /// animated ones: skyland gets the final height once, not every frame.
    /// One value for every display: the notch height when a notched display shows it.
    private func tellSkylandBarHeight() {
        let bar = model.bar
        var height = 0
        if bar.position != "bottom" {
            let notched = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
            let tallest = notched && bar.notchDisplayHeight > 0 ? max(bar.height, bar.notchDisplayHeight) : bar.height
            height = Int((tallest + bar.yOffset).rounded(.up))
        }
        guard height != skylandBarHeight else { return }
        skylandBarHeight = height
        SkylandSocket.run(["bar-height", String(height)])
    }

    private func makeWindow(_ display: Int) -> BarWindow {
        let window = BarWindow(display: display)
        let view = window.view, id = ObjectIdentifier(window)
        view.onItemEntered = { [unowned self] name in
            if name.hasPrefix("menubar.") {
                self.menuHovered = name
                return self.setNeedsLayout()
            }
            if self.model.setHovered(name) { self.startFrames() }
            self.scripts.run(self.model.scripts(for: "mouse.entered", only: name))
        }
        view.onItemExited = { [unowned self] name in
            if self.menuHovered == name {
                self.menuHovered = nil
                return self.setNeedsLayout()
            }
            if self.model.hovered == name, self.model.setHovered(nil) { self.startFrames() }
            self.scripts.run(self.model.scripts(for: "mouse.exited", only: name))
        }
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
        view.onClick = { [unowned self, unowned view] name, button, modifier in
            if button == "left", let workspace = self.model.workspace(of: name) { SkylandSocket.run(["workspace", workspace]) }
            if name.hasPrefix("menubar.") { return self.dropMenu(name, in: view) }
            if button == "left", let extra = self.model.item(named: name)?.props.menuExtra, !extra.isEmpty {
                return AppMenu.pressExtra(extra) { pid in
                    self.menuBarCover.show(under: self.windows.map(\.panel), height: self.model.bar.height, menuOf: pid)
                }
            }
            if button == "left", let menubar = self.model.item(named: name)?.props.menubar, !menubar.isEmpty {
                if self.menuOpen { return self.setMenuBar(open: false) }
                if self.model.bar.position != "bottom" { return self.setMenuBar(open: true, trigger: name, display: display) }
                if let placed = view.items.first(where: { $0.name == name }) { return AppMenu.popUp(under: placed.rect, in: view) }
            }
            if self.menuOpen { self.setMenuBar(open: false) } // a click elsewhere on the bar
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
            // over workspaces: the next or previous one, at most every quarter second (trackpads send many)
            let now = ProcessInfo.processInfo.systemUptime
            if let name, self.model.scrollsWorkspaces(name), now - self.lastWorkspaceScroll > 0.25 {
                self.lastWorkspaceScroll = now
                SkylandSocket.run(["workspace", "--wrap-around", delta > 0 ? "prev" : "next"])
            }
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
            let extra = menuBar?.display == window.display ? menuExtra : 0
            if window.extra != extra {
                window.extra = extra
                window.configure(bar, screen: NSScreen.screens[window.display - 1])
            }
            let frame = window.panel.frame
            let width = Double(frame.width), height = Double(frame.height) - extra
            let spaces = model.currentSpaces[window.display].map { [$0] } ?? []
            let shown = model.items.filter { item in
                item.kind != "bracket" && item.kind != "workspaces" && item.props.drawing && itemPositions.contains(item.props.position)
                    && item.props.isShown(onDisplay: window.display, activeDisplay: active)
                    && (item.kind == "space" || item.props.isShown(onSpaces: spaces))
            }
            let props = shown.map { model.displayed($0) }
            let middles = zip(shown, props).map { middle($0, $1) }
            let lengths = zip(props, middles).map { Layout.length(of: $0, middle: $1, measure: Fonts.width, image: Images.width) }
            let slots = shown.indices.map { index in
                Layout.Slot(name: shown[index].name, position: props[index].position, length: lengths[index],
                            paddingLeft: props[index].background.paddingLeft, paddingRight: props[index].background.paddingRight,
                            fixed: props[index].width != nil)
            }
            let xs = Layout.place(slots, width: width, paddingLeft: bar.paddingLeft, paddingRight: bar.paddingRight,
                                  notchWidth: bar.notchWidth, notchOffset: bar.notchOffset)
            var items: [PlacedItem] = []
            for index in shown.indices {
                guard let x = xs[shown[index].name] else { continue }
                items.append(placed(shown[index], props[index], x: x, length: lengths[index], top: 0, height: height, middle: middles[index]))
                frames[shown[index].name, default: [:]]["display-\(window.display)"] = Box(x: x, y: 0, width: lengths[index], height: height)
                anchors[shown[index].name] = (NSRect(x: frame.minX + x, y: frame.maxY - height, width: lengths[index], height: height), window.display)
            }
            window.view.show(withMenuBar(brackets(around: items, height: height) + items, display: window.display, row: height),
                             style: PanelStyle(bar: bar))
            window.updateGlass(glassSettings(bar)) // every layout: the metal glass follows the window
        }
        layoutPopups(bar: bar, anchors: &anchors, frames: &frames)
        layoutNotch(frames: &frames)
        model.frames = frames
        updateScrolling()
    }

    /// Each bracket around its members on this bar, behind them, with their outer background
    /// paddings (the first one's padding_left, the last one's padding_right),
    /// then its own background paddings outward (skylandbar's: room at a group's ends only)
    private func brackets(around items: [PlacedItem], height: Double) -> [PlacedItem] {
        model.items.filter { $0.kind == "bracket" && $0.props.drawing }.compactMap { bracket in
            let members = Set(model.members(of: bracket))
            let inside = items.filter { members.contains($0.name) }
            guard let first = inside.min(by: { $0.x < $1.x }), let last = inside.max(by: { $0.x + $0.length < $1.x + $1.length }) else { return nil }
            let own = model.displayed(bracket).background
            let start = first.x - first.props.background.paddingLeft - own.paddingLeft
            let end = last.x + last.length + last.props.background.paddingRight + own.paddingRight
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
                        paddingLeft: props[index].background.paddingLeft, paddingRight: props[index].background.paddingRight,
                        fixed: props[index].width != nil)
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
        window.view.show(items, style: PanelStyle(popup: popup, fontSmoothing: bar.fontSmoothing))
        window.updateGlass(glassSettings(bar))
        window.panel.orderFrontRegardless()
    }

    // MARK: menu bar

    /// Opens (the frontmost app's menus read now) or closes the menu bar in `bracket`'s glass,
    /// on a spring as the notch; a click in another app closes it.
    private func setMenuBar(open: Bool, trigger: String = "", display: Int = 0) {
        guard open != menuOpen else { return }
        if open {
            let menus = AppMenu.menus()
            guard !menus.isEmpty else { return }
            menuBar = (trigger, model.item(named: trigger)?.props.menubar ?? "", display, menus)
            menuMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [unowned self] _ in
                self.setMenuBar(open: false)
            }
        } else if let monitor = menuMonitor {
            NSEvent.removeMonitor(monitor)
            menuMonitor = nil
        }
        menuOpen = open
        menuMove = (menuProgress, open ? 1 : 0, ProcessInfo.processInfo.systemUptime)
        if menuTicker == nil {
            menuTicker = FrameTicker(view: windows.first { $0.display == menuBar?.display }?.view) { [unowned self] in self.menuFrame() }
        }
    }

    private func menuFrame() {
        guard let move = menuMove else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - move.start
        // quick: a little past open, closing without a bounce
        let spring = move.to == 1 ? Spring(response: 0.32, damping: 0.75) : Spring(response: 0.28, damping: 1)
        let done = model.reduceMotion || elapsed >= spring.duration
        menuProgress = done ? move.to : mix(move.from, move.to, spring.value(elapsed))
        if done {
            menuMove = nil
            menuTicker?.stop()
            menuTicker = nil
            if move.to == 0 { menuBar = nil }
        }
        layoutNow()
    }

    /// The room the open menu bar takes below the bar: its second row, as far as it dropped.
    private var menuExtra: Double {
        guard let menuBar, let trigger = model.item(named: menuBar.trigger) else { return 0 }
        let own = model.displayed(trigger).background.height
        let height = own > 0 ? own : model.item(named: menuBar.bracket).map { model.displayed($0).background.height } ?? model.bar.height - 4
        return (height + (menuGap ?? model.bar.glassSpacing + 2)) * max(0, min(1, menuProgress / 0.45))
    }

    /// the gap withMenuBar keeps between the rows (the item's own off the bracket)
    private var menuGap: Double?

    /// The open menu bar, as one shape of glass with the item that has `menubar`: its bubble
    /// drops down a row (a drop of glass, 0...0.45 of the spring), then a row runs right from
    /// it under the other items (0.35...1), as far as the menus' titles go, and to the end of
    /// the bracket `menubar` names; the titles show as the row reaches them. Rows and the
    /// item stay `gap` off the other glass: shapes nearer than glass_spacing would melt.
    private func withMenuBar(_ items: [PlacedItem], display: Int, row: Double) -> [PlacedItem] {
        guard let menuBar, menuBar.display == display, let item = model.item(named: menuBar.trigger),
              let index = items.firstIndex(where: { $0.name == menuBar.trigger }) else { return items }
        var items = items
        let trigger = items[index]
        let bracket = items.first { $0.name == menuBar.bracket }
        let height = trigger.props.background.height > 0 ? trigger.props.background.height : bracket?.props.background.height ?? row - 4
        // the row runs as far under the bracket as the item stands off it: the same gap both
        // ways (the item's padding_right sets it); glass_spacing + 2 without a bracket
        let gap = bracket.map { max(2, $0.x - (trigger.x + trigger.length)) } ?? model.bar.glassSpacing + 2
        menuGap = gap
        let p = menuProgress
        let drop = max(0, min(1, p / 0.45)), run = max(0, (p - 0.35) / 0.65) // run overshoots with the spring
        let down = (height + gap) * drop
        var glass = BackgroundProps()
        glass.drawing = true
        glass.glass = bracket?.props.background.glass ?? "regular"
        glass.color = bracket?.props.background.color ?? .clear
        let opacity = model.displayed(item).menubarOpacity
        if opacity > 0 { glass.color = ARGB(UInt32((opacity * 255).rounded()) << 24 | (Self.appearance == "dark" ? 0 : 0xFF_FFFF)) }
        glass.cornerRadius = height / 2
        // the L's inner corner: concentric to the bracket's capsule, its radius plus the gap
        glass.fillet = (bracket?.props.background.height ?? height) / 2 + gap
        var props = trigger.props
        props.background.glass = "off" // its hover glass: the drop's now
        props.background.color = .clear // else its hover tint, without glass, a square (corner_radius 0)
        items[index] = PlacedItem(name: trigger.name, kind: trigger.kind, x: trigger.x, length: trigger.length, top: trigger.top,
                                  height: trigger.height, props: props, middle: trigger.middle)
        var label = model.displayed(item).label
        label.drawing = true
        // room around each title for its hover drop
        label.paddingLeft = max(label.paddingLeft, 10)
        label.paddingRight = max(label.paddingRight, 10)
        let top = (row - height) / 2 + height + gap // the second row's
        var titles: [PlacedItem] = []
        var x = trigger.x + trigger.length + 4
        for (offset, menu) in menuBar.menus.enumerated() {
            let name = "menubar.\(offset)"
            var title = ItemProps()
            title.icon.drawing = false
            title.label = label
            title.label.string = menu.title
            if offset == 0 { title.label.font.style = "Bold" }
            if name == menuShown || (menuShown == nil && name == menuHovered) {
                title.background.drawing = true
                title.background.glass = "hover"
                title.background.height = height - 8
                title.background.color = ARGB(label.color.value & 0x00FF_FFFF | 0x2400_0000)
            }
            let length = Layout.length(of: title, measure: Fonts.width, image: Images.width)
            titles.append(PlacedItem(name: name, kind: "item", x: x, length: length, top: top, height: height, props: title))
            x += length
        }
        let end = max(x + height / 2, bracket.map { $0.x + $0.length } ?? 0)
        let reach = trigger.x + trigger.length + (end - trigger.x - trigger.length) * run
        // glass only: a bracket draws its background, nothing else
        let shape = { (name: String, x: Double, length: Double, top: Double, height: Double) -> PlacedItem in
            var props = ItemProps()
            props.background = glass
            props.background.height = height
            return PlacedItem(name: name, kind: "bracket", x: x, length: length, top: top, height: height, props: props)
        }
        var shapes = [shape("menubar.drop", trigger.x, trigger.length, (row - height) / 2, height + down)]
        if run > 0 { shapes.append(shape("menubar.row", trigger.x, reach - trigger.x, top, height)) }
        let shown = menuOpen ? titles.filter { $0.x + $0.length <= reach } : []
        return shapes + items + shown
    }

    /// A title clicked: its menu drops under it; choosing an item closes the menu bar.
    private func dropMenu(_ name: String, in view: BarView) {
        guard let menuBar, let index = Int(name.dropFirst("menubar.".count)), menuBar.menus.indices.contains(index),
              let placed = view.items.first(where: { $0.name == name }) else { return }
        menuShown = name
        layoutNow()
        let menu = menuBar.menus[index]
        let chosen = AppMenu.popUp(menu.title, menu.menu, under: placed.rect, in: view) // until the menu closes
        menuShown = nil
        if chosen { setMenuBar(open: false) } else { setNeedsLayout() }
    }

    /// Animations or not: the bar's `motion`, and with `auto` macOS's Reduce Motion.
    private func updateMotion() {
        switch model.bar.motion {
            case "full": model.reduceMotion = false
            case "reduced": model.reduceMotion = true
            default: model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    private func glassSettings(_ bar: BarProps) -> GlassSettings {
        var settings = GlassSettings(bar: bar)
        settings.reduceMotion = model.reduceMotion
        return settings
    }

    // MARK: notch

    /// The notch's open state changed (the mouse, or `notch.open` from a script), or its
    /// options: it animates there and its scripts get notch_open / notch_close.
    private func notchChanged() {
        guard let notch = model.notch else {
            notchWindow?.panel.orderOut(nil)
            notchWindow = nil
            return
        }
        let open = notch.options["open"] == "on"
        if open != notchOpen {
            notchOpen = open
            let frames = notch.options["animation_frames"].flatMap(Double.init) ?? 20
            let name = notch.options["animation"] ?? "spring"
            // boringNotch's springs: a little past open, closing without a bounce
            let spring = name == "spring" ? (open ? Spring(response: 0.42, damping: 0.8) : Spring(response: 0.45, damping: 1)) : nil
            let duration = model.reduceMotion ? 0 : spring?.duration ?? frames / framesPerSecond // Reduce Motion: at once
            notchMove = (notchProgress, open ? 1 : 0, ProcessInfo.processInfo.systemUptime, duration, Curve(rawValue: name) ?? .tanh, spring)
            scripts.run(model.scripts(for: open ? "notch_open" : "notch_close"))
            if notchTicker == nil {
                notchTicker = FrameTicker(view: notchWindow?.view) { [unowned self] in self.notchFrame() }
            }
        }
        setNeedsLayout()
    }

    private func notchFrame() {
        guard let move = notchMove else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - move.start
        let t = move.duration > 0 ? elapsed / move.duration : 1
        notchProgress = mix(move.from, move.to, move.spring.map { t >= 1 ? 1 : $0.value(elapsed) } ?? move.curve.value(t))
        if t >= 1 {
            notchProgress = move.to
            notchMove = nil
            notchTicker?.stop()
            notchTicker = nil
        }
        layoutNow()
    }

    /// The mouse over the notch: it opens after `notch.open_delay` (0.3 s) and closes
    /// `notch.close_delay` (0.1 s) after the mouse leaves it, as boringNotch.
    private func hoverNotch(_ inside: Bool) {
        notchHover?.cancel()
        guard let notch = model.notch, (notch.options["open"] == "on") != inside else { return }
        let delay = notch.options[inside ? "open_delay" : "close_delay"].flatMap(Double.init) ?? (inside ? 0.3 : 0.1)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.setNotchOpen(inside) else { return }
            self.notchChanged()
        }
        notchHover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func isOn(_ value: String?) -> Bool { ["on", "yes", "true", "1"].contains(value ?? "") }

    /// The display with a notch, and the notch (AppKit coordinates); with `notch.fake=on`,
    /// a notch-sized place at the top middle of the main display when none has one.
    private func notchPlace(fake: Bool) -> (screen: NSScreen, display: Int, rect: NSRect)? {
        for (index, screen) in NSScreen.screens.enumerated() where screen.safeAreaInsets.top > 0 {
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { continue }
            let height = screen.safeAreaInsets.top
            let rect = NSRect(x: screen.frame.minX + left.width, y: screen.frame.maxY - height,
                              width: screen.frame.width - left.width - right.width, height: height)
            return (screen, index + 1, rect)
        }
        guard fake, let screen = NSScreen.screens.first else { return nil }
        let height = max(24, screen.frame.maxY - screen.visibleFrame.maxY) // the menu bar's
        return (screen, 1, NSRect(x: screen.frame.midX - 92, y: screen.frame.maxY - height, width: 184, height: height))
    }

    /// The notch's window, between the notch's own size (closed: black on the camera's
    /// black) and the size its items need, `notch.width` / `notch.height` at least.
    /// The items (`position=popup.<notch>`) show once it is open.
    private func layoutNotch(frames: inout [String: [String: Box]]) {
        guard let notch = model.notch, let place = notchPlace(fake: isOn(notch.options["fake"])) else {
            notchWindow?.panel.orderOut(nil)
            return
        }
        let option = { (name: String, fallback: Double) in notch.options[name].flatMap(Double.init) ?? fallback }
        // boringNotch's shape: closed, top curves 6 and bottom corners 14; open, 19 and 24
        let flare = option("closed_flare", 6), openFlare = option("flare", 19), padding = option("padding", 12)
        let row = option("row_height", place.rect.height)
        let children = model.popupItems(of: notch.name).filter { $0.props.drawing }
        let props = children.map { model.displayed($0) }
        let middles = zip(children, props).map { middle($0, $1) }
        let lengths = zip(props, middles).map { Layout.length(of: $0, middle: $1, measure: Fonts.width, image: Images.width) }
        // notch.bottom_right: that item in the open notch's bottom right corner, out of the rows
        let corner = children.firstIndex { $0.name == notch.options["bottom_right"] }
        let slots = children.indices.filter { $0 != corner }.map { index in
            Layout.Slot(name: children[index].name, position: "popup", length: lengths[index],
                        paddingLeft: props[index].background.paddingLeft, paddingRight: props[index].background.paddingRight,
                        fixed: props[index].width != nil)
        }
        let horizontal = isOn(notch.options["horizontal"])
        let laid = Layout.popup(slots, horizontal: horizontal, rowHeight: row, inset: 0)
        // closed: the camera's notch, or closed_width x closed_height (wider, it shows around it)
        let closed = (width: option("closed_width", Double(place.rect.width)) + 2 * flare,
                      height: option("closed_height", Double(place.rect.height)), radius: option("closed_corner_radius", 14))
        let open = (width: max(option("width", 0), laid.width + 2 * padding) + 2 * openFlare,
                    height: max(option("height", 0), closed.height + laid.height + padding),
                    radius: option("corner_radius", 24))
        let p = notchProgress
        let width = max(closed.width, mix(closed.width, open.width, p)), height = mix(closed.height, open.height, p)
        let frame = NSRect(x: Double(place.rect.midX) - width / 2, y: Double(place.screen.frame.maxY) - height, width: width, height: height)

        let window = notchWindow ?? makeWindow(place.display)
        if notchWindow == nil {
            window.view.onBarEntered = { [unowned self] in self.hoverNotch(true) }
            window.view.onBarExited = { [unowned self] in self.hoverNotch(false) }
            notchWindow = window
        }
        window.configureNotch(frame: frame, open: p > 0)
        var style = PanelStyle()
        style.color = notch.options["color"].flatMap(ARGB.parse) ?? .black
        style.cornerRadius = mix(closed.radius, open.radius, p)
        style.notch = true
        style.flare = mix(flare, openFlare, min(p, 1))
        // notch.glass: the same shape on the same spring, of glass (the bar's engine, notch.color
        // its tint), closed too: glass around the camera's notch (closed_width wider than it);
        // its top runs off the screen so only the bottom corners round
        if let glass = notch.options["glass"], glass != "off" {
            style.glass = glass
            style.color = notch.options["color"].flatMap(ARGB.parse) ?? .clear
            style.glassRect = NSRect(x: style.flare, y: -style.cornerRadius, width: width - 2 * style.flare, height: height + style.cornerRadius)
        }
        var items: [PlacedItem] = []
        if notchOpen && p >= 0.95 { // the items once it is (nearly) open, through the spring's overshoot
            let left = (width - laid.width) / 2, top = closed.height + max(0, (height - closed.height - laid.height) / 2)
            for index in children.indices {
                guard let place = laid.places[children[index].name] else { continue }
                items.append(placed(children[index], props[index], x: left + place.x, length: lengths[index], top: top + place.y, height: row,
                                    middle: middles[index]))
                frames[children[index].name, default: [:]]["notch"] = Box(x: left + place.x, y: top + place.y, width: lengths[index], height: row)
            }
            if let corner {
                let x = width - style.flare - padding - lengths[corner], y = height - padding / 2 - row
                items.append(placed(children[corner], props[corner], x: x, length: lengths[corner], top: y, height: row, middle: middles[corner]))
                frames[children[corner].name, default: [:]]["notch"] = Box(x: x, y: y, width: lengths[corner], height: row)
            }
        }
        window.view.show(items, style: style)
        var settings = glassSettings(model.bar)
        if let glass = notch.options["glass"], glass != "off" { // what is behind the open notch, ready before it opens
            settings.captureArea = NSRect(x: Double(place.rect.midX) - open.width / 2, y: Double(place.screen.frame.maxY) - open.height,
                                          width: open.width, height: open.height)
        }
        window.updateGlass(settings) // its glass, or none once closed
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
