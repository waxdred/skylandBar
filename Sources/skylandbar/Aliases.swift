import AppKit
import ScreenCaptureKit

/// Menu bar items (the windows of the status layer), which `--add alias` copies onto the
/// bar. Their names need Screen Recording, like sketchybar's aliases.
enum MenuItems {
    struct Entry {
        let owner: String
        let name: String
        let windowID: CGWindowID
        /// global coordinates, top-left origin
        let frame: CGRect

        var alias: String { "\(owner),\(name)" }
    }

    static func list() -> [Entry] {
        guard let infos = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = Int(getpid())
        var seen = Set<String>()
        return infos.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  info[kCGWindowOwnerPID as String] as? Int != me,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0 else { return nil }
            let entry = Entry(owner: owner, name: info[kCGWindowName as String] as? String ?? "", windowID: CGWindowID(number), frame: frame)
            // one per item: a menu bar on each display has its own copy
            return seen.insert(entry.alias).inserted ? entry : nil
        }
    }

    /// "Owner,Name", or "Owner" for its first item.
    static func find(_ alias: String, in entries: [Entry]? = nil) -> Entry? {
        let parts = alias.split(separator: ",", maxSplits: 1).map(String.init)
        guard let owner = parts.first else { return nil }
        return (entries ?? list()).first { $0.owner == owner && (parts.count == 1 || $0.name == parts[1]) }
    }

    /// A click on the real item (its menu opens), the pointer put back after.
    static func click(_ alias: String) {
        guard let entry = find(alias) else { return }
        let back = CGEvent(source: nil)?.location
        let point = CGPoint(x: entry.frame.midX, y: entry.frame.midY)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if let back { CGWarpMouseCursorPosition(back) }
    }
}

/// The captured images of the aliases, refreshed by the bar's timer.
final class AliasCapture {
    private(set) var images: [String: NSImage] = [:]
    var onChange: (() -> Void)?

    /// The width it takes on the bar, before `alias.scale`.
    func width(_ alias: String) -> Double { Double(images[alias]?.size.width ?? 0) }

    func forget(except aliases: [String]) {
        images = images.filter { aliases.contains($0.key) }
    }

    /// ScreenCaptureKit's windows by id: its list is costly, asked again only for a window
    /// it does not know yet (an app started, a menu bar item came back)
    private var known: [CGWindowID: SCWindow] = [:]

    func refresh(_ aliases: [String]) {
        let entries = MenuItems.list() // once for all the aliases
        let wanted = aliases.compactMap { alias in MenuItems.find(alias, in: entries).map { (alias, $0) } }
        guard !wanted.isEmpty else { return }
        if wanted.allSatisfy({ known[$0.1.windowID] != nil }) {
            capture(wanted)
            return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, _ in
            guard let content else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.known = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
                self.capture(wanted)
            }
        }
    }

    private func capture(_ wanted: [(String, MenuItems.Entry)]) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for (alias, entry) in wanted {
            guard let window = known[entry.windowID] else { continue }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(entry.frame.width * scale)
            configuration.height = Int(entry.frame.height * scale)
            configuration.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                             configuration: configuration)
            { [weak self] image, _ in
                guard let image else { return }
                DispatchQueue.main.async {
                    self?.images[alias] = NSImage(cgImage: image, size: entry.frame.size)
                    self?.onChange?()
                }
            }
        }
    }
}
