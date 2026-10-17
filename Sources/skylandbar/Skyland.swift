import AppKit
import SkylandBarCore

/// skyland's (or AeroSpace's) events, through its `subscribe` on its socket: workspace,
/// focus, monitor and mode changes reach the bar as they happen, with no
/// `exec-on-workspace-change` script. The connection comes back when skyland restarts.
///
/// The socket speaks AeroSpace's protocol: a UInt32 version each way, then
/// length-prefixed JSON (UInt32 length, native byte order): our request, then its events.
final class SkylandEvents {
    /// (event, env with INFO)
    var onEvent: ((String, [String: String]) -> Void)?
    private static let version: UInt32 = 1
    private static var sockets: [String] {
        ["/tmp/com.waxdred.skyland-\(NSUserName()).sock", "/tmp/bobko.aerospace-\(NSUserName()).sock"]
    }

    func start() {
        let thread = Thread { [weak self] in
            while self != nil {
                for path in Self.sockets where FileManager.default.fileExists(atPath: path) {
                    self?.listen(path)
                }
                Thread.sleep(forTimeInterval: 3) // not running, or gone: try again
            }
        }
        thread.name = "skylandbar skyland events"
        thread.start()
    }

    /// Reads events until the connection ends.
    private func listen(_ path: String) {
        guard let fd = Self.connect(path) else { return }
        defer { close(fd) }
        var version = Self.version
        guard Socket.writeAll(fd, Data(bytes: &version, count: 4)), let theirs = Self.readUInt32(fd), theirs == Self.version else { return }
        let request: [String: Any] = ["args": ["subscribe", "--all"], "stdin": "", "windowId": NSNull(), "workspace": NSNull()]
        guard let json = try? JSONSerialization.data(withJSONObject: request) else { return }
        var length = UInt32(json.count)
        guard Socket.writeAll(fd, Data(bytes: &length, count: 4) + json) else { return }
        while let size = Self.readUInt32(fd), size < 1 << 20, let message = Self.read(fd, Int(size)) {
            guard let event = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else { continue }
            let info = String(decoding: message, as: UTF8.self)
            let events = skylandEvent(event)
            DispatchQueue.main.async { [weak self] in
                for (name, env) in events { self?.onEvent?(name, env.merging(["INFO": info]) { a, _ in a }) }
            }
        }
    }

    private static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return nil }
        Socket.noSigPipe(fd)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.prefix($0.count - 1)) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    private static func read(_ fd: Int32, _ size: Int) -> Data? {
        var data = Data(count: size)
        var offset = 0
        while offset < size {
            let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + offset, size - offset) }
            if count <= 0 { return nil }
            offset += count
        }
        return data
    }

    private static func readUInt32(_ fd: Int32) -> UInt32? {
        read(fd, 4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    }
}

/// The windows on screen, for the focused display (`display=active`) and
/// space_windows_change.
enum Windows {
    private struct Window {
        let pid: pid_t
        let app: String
        /// global coordinates, top-left origin
        let frame: CGRect
    }

    private static func onScreen() -> [Window] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 1, frame.height > 1 else { return nil }
            return Window(pid: pid_t(pid), app: info[kCGWindowOwnerName as String] as? String ?? "", frame: frame)
        }
    }

    /// The display (1-based, NSScreen order) of a top-left global point.
    private static func display(of point: CGPoint) -> Int? {
        guard let height = NSScreen.screens.first?.frame.height else { return nil }
        let flipped = NSPoint(x: point.x, y: height - point.y)
        return NSScreen.screens.firstIndex { $0.frame.contains(flipped) }.map { $0 + 1 }
    }

    /// The display of the frontmost app's top window, nil when it has none on screen.
    static func focusedDisplay() -> Int? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = onScreen().first(where: { $0.pid == pid }) else { return nil }
        return display(of: CGPoint(x: window.frame.midX, y: window.frame.midY))
    }

    /// The apps with windows on each display's shown space, and how many: display -> app -> count.
    static func appsByDisplay() -> [Int: [String: Int]] {
        var result: [Int: [String: Int]] = [:]
        for window in onScreen() {
            guard let display = display(of: CGPoint(x: window.frame.midX, y: window.frame.midY)) else { continue }
            result[display, default: [:]][window.app, default: 0] += 1
        }
        return result
    }
}
