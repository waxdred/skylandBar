import AppKit

/// An item's `menubar`: the frontmost app's menus (File, Edit...), read through Accessibility,
/// as a row of titles in a bracket's glass (BarApp), or with `on` as a native menu with the
/// status extras (Wi-Fi, Control Center, third-party items). Each submenu is read when it opens (menus change with the app's state);
/// choosing an item presses the real one.
enum AppMenu {
    /// Kept while the menu is open: NSMenu holds its delegate weakly.
    private static let filler = Filler()

    /// The frontmost app's menus, its own first (Apple's left out), each title with its
    /// menu; empty without Accessibility (macOS asks for it).
    static func menus() -> [(title: String, menu: AXUIElement?)] {
        guard trusted() else { return [] }
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        return children(attribute(root, kAXMenuBarAttribute)).dropFirst().compactMap { bar in
            let title = string(bar, kAXTitleAttribute)
            return title.isEmpty ? nil : (title, children(bar).first)
        }
    }

    /// One of `menus()` dropped from `rect` (in `view`, flipped); true when an item was
    /// chosen, false when it was dismissed.
    static func popUp(_ title: String, _ element: AXUIElement?, under rect: NSRect, in view: NSView) -> Bool {
        filler.chosen = false
        submenu(title, element).popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: view)
        return filler.chosen
    }

    /// Every menu as a submenu, then the status extras: the item's menu without a bracket.
    static func popUp(under rect: NSRect, in view: NSView) {
        let menu = NSMenu()
        for (title, element) in menus() {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu(title, element)
        }
        let extras = statusExtras()
        if !extras.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Status"))
            for (title, element) in extras { menu.addItem(pressing(element, title: title)) }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: view)
    }

    /// An item's `menu_extra` clicked: that menu bar extra pressed, its own menu opens (Wi-Fi's
    /// switch and networks, the battery's, Control Center...). `name`: the end of its
    /// identifier (com.apple.menuextra.wifi), else a word of its title or description.
    /// `willPress`: on the main thread, with the item's app, just before.
    static func pressExtra(_ name: String, willPress: @escaping (pid_t) -> Void = { _ in }) {
        guard trusted() else { return }
        // off the main thread: pressing waits on the app, the bar keeps drawing
        DispatchQueue.global(qos: .userInitiated).async {
            let key = name.lowercased(), extras = statusExtras()
            let hit = extras.first { string($0.1, "AXIdentifier").lowercased().hasSuffix("." + key) }
                ?? extras.first { $0.0.lowercased().contains(key) }
            guard let hit else {
                let known = extras.map { "\($0.0) (\(string($0.1, "AXIdentifier")))" }.joined(separator: ", ")
                return FileHandle.standardError.write(Data("skylandbar: menu_extra '\(name)': no such menu bar item, there are: \(known)\n".utf8))
            }
            var pid: pid_t = 0
            AXUIElementGetPid(hit.1, &pid)
            DispatchQueue.main.sync { willPress(pid) }
            AXUIElementPerformAction(hit.1, kAXPressAction as CFString)
        }
    }

    private static func trusted() -> Bool {
        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) { return true }
        FileHandle.standardError.write(Data("skylandbar: menubar: no Accessibility permission\n".utf8))
        return false
    }

    /// Every app's menu bar extras, named by their title, description or app.
    private static func statusExtras() -> [(String, AXUIElement)] {
        NSWorkspace.shared.runningApplications.flatMap { app -> [(String, AXUIElement)] in
            guard app.processIdentifier != getpid() else { return [] }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            // ponytail: one AX call per running app on each open, cache the list if it gets slow
            AXUIElementSetMessagingTimeout(root, 0.1)
            return children(attribute(root, "AXExtrasMenuBar" as CFString)).flatMap(menuBarItems).map { extra in
                let title = [string(extra, kAXTitleAttribute), string(extra, kAXDescriptionAttribute)]
                    .first { !$0.isEmpty } ?? app.localizedName ?? "?"
                return (title, extra)
            }
        }
    }

    /// The menu bar items in an extras bar's child: itself, or (macOS 26's Control Center
    /// items: a hosting group around each) the ones inside it.
    private static func menuBarItems(_ element: AXUIElement) -> [AXUIElement] {
        if string(element, kAXRoleAttribute) != "AXGroup" { return [element] }
        return children(element).filter { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }
    }

    private static func submenu(_ title: String, _ element: AXUIElement?) -> NSMenu {
        let menu = Submenu(title: title)
        menu.element = element
        menu.delegate = filler
        // one placeholder: AppKit only opens a submenu that has items
        menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        return menu
    }

    private final class Submenu: NSMenu {
        var element: AXUIElement?
    }

    private final class Filler: NSObject, NSMenuDelegate {
        var chosen = false

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let menu = menu as? Submenu else { return }
            menu.removeAllItems()
            for child in children(menu.element) {
                let title = string(child, kAXTitleAttribute)
                if title.isEmpty {
                    if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
                    continue
                }
                let item = pressing(child, title: title)
                item.isEnabled = attribute(child, kAXEnabledAttribute) as? Bool ?? true
                if !string(child, kAXMenuItemMarkCharAttribute).isEmpty { item.state = .on }
                item.keyEquivalent = string(child, kAXMenuItemCmdCharAttribute).lowercased()
                item.keyEquivalentModifierMask = modifiers(attribute(child, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0)
                if let sub = children(child).first { item.submenu = submenu(title, sub) }
                menu.addItem(item)
            }
        }

        @objc func press(_ sender: NSMenuItem) {
            guard let element = sender.representedObject else { return }
            chosen = true
            // after the menu is gone: the app's own menu tracking would close ours
            DispatchQueue.main.async { AXUIElementPerformAction(element as! AXUIElement, kAXPressAction as CFString) }
        }
    }

    private static func pressing(_ element: AXUIElement, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Filler.press(_:)), keyEquivalent: "")
        item.target = filler
        item.representedObject = element
        return item
    }

    /// AX's command modifiers: ⌘ unless bit 3 (no ⌘), plus shift (1), option (2), control (4).
    private static func modifiers(_ ax: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = ax & 8 == 0 ? [.command] : []
        if ax & 1 != 0 { flags.insert(.shift) }
        if ax & 2 != 0 { flags.insert(.option) }
        if ax & 4 != 0 { flags.insert(.control) }
        return flags
    }

    private static func attribute(_ element: AXUIElement?, _ name: String) -> AnyObject? {
        attribute(element, name as CFString)
    }

    private static func attribute(_ element: AXUIElement?, _ name: CFString) -> AnyObject? {
        guard let element else { return nil }
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private static func children(_ element: AnyObject?) -> [AXUIElement] {
        guard let element, CFGetTypeID(element) == AXUIElementGetTypeID() else { return [] }
        return attribute((element as! AXUIElement), kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}

/// An Apple menu opened from the bar (`menu_extra`) slides macOS's hidden menu bar in, under
/// the bar's glass: covered meanwhile, between the two, by the desktop picture (what is there
/// without it: windows stay below the bar), until the menu is gone and the menu bar slid out.
final class MenuBarCover {
    private var windows: [NSWindow] = []
    private var timer: Timer?
    /// skyland hides the bar while macOS's menu bar is down (`--bar hidden=on`): not while it
    /// is covered; the bar takes skyland's word again once the cover is gone
    var isShown: Bool { !windows.isEmpty }
    var onHide: (() -> Void)?

    /// Over macOS's menu bar, under `bars`, while `pid` (the menu's app) shows a menu.
    func show(under bars: [NSWindow], height: Double, menuOf pid: pid_t) {
        hide()
        for screen in NSScreen.screens {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) else { continue }
            let height = max(height, screen.safeAreaInsets.top, 25) // macOS's menu bar, at least
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.contentView = Strip(image: image, screen: screen.frame.size, height: height)
            window.orderFrontRegardless()
            windows.append(window)
        }
        for bar in bars where bar.isVisible { bar.orderFrontRegardless() }
        // its menu: a window of that app over the status bar's level; gone (or never seen
        // within a second): the menu bar slides out, then the cover goes
        var seen = false, waited = 0.0
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            waited += 0.15
            let open = Self.hasMenu(pid)
            if open { seen = true }
            if open || (!seen && waited < 1) { return }
            self?.timer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.hide() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        guard isShown else { return }
        for window in windows { window.orderOut(nil) }
        windows = []
        onHide?()
    }

    private static func hasMenu(_ pid: pid_t) -> Bool {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let status = Int(CGWindowLevelForKey(.statusWindow))
        return infos.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) && ($0[kCGWindowLayer as String] as? Int ?? 0) > status }
    }

    /// The top of the desktop picture as macOS fills the screen with it.
    // ponytail: always "fill screen"; a picture set to fit or center shows a little off
    private final class Strip: NSView {
        let image: NSImage
        let screen: NSSize
        let height: Double

        init(image: NSImage, screen: NSSize, height: Double) {
            self.image = image
            self.screen = screen
            self.height = height
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            let scale = max(screen.width / image.size.width, screen.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = NSPoint(x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2 - (screen.height - height))
            image.draw(in: NSRect(origin: origin, size: size))
        }
    }
}
