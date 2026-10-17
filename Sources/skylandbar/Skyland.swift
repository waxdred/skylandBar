import AppKit
import SkylandBarCore

/// skyland's (or AeroSpace's) socket: AeroSpace's protocol, a UInt32 version each way,
/// then length-prefixed JSON (UInt32 length, native byte order) both ways.
enum SkylandSocket {
    private static let version: UInt32 = 1
    static var paths: [String] {
        ["/tmp/com.waxdred.skyland-\(NSUserName()).sock", "/tmp/bobko.aerospace-\(NSUserName()).sock"]
    }

    /// A connection past the version check, to the first window manager that answers.
    static func open() -> Int32? {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            guard let fd = connect(path) else { continue }
            var mine = version
            if Socket.writeAll(fd, Data(bytes: &mine, count: 4)), readUInt32(fd) == version { return fd }
            close(fd)
        }
        return nil
    }

    /// Sends a command (its arguments, as on the aerospace CLI).
    static func send(_ fd: Int32, _ args: [String]) -> Bool {
        let request: [String: Any] = ["args": args, "stdin": "", "windowId": NSNull(), "workspace": NSNull()]
        guard let json = try? JSONSerialization.data(withJSONObject: request) else { return false }
        var length = UInt32(json.count)
        return Socket.writeAll(fd, Data(bytes: &length, count: 4) + json)
    }

    /// The next length-prefixed message.
    static func receive(_ fd: Int32) -> Data? {
        guard let size = readUInt32(fd), size < 1 << 24 else { return nil }
        return read(fd, Int(size))
    }

    /// Runs a command on a connection of its own, off the main thread; `done` gets its
    /// output on the main thread, nil when it failed or nothing answers.
    static func run(_ args: [String], done: ((String?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            var output: String? = nil
            if let fd = open() {
                if send(fd, args), let answer = receive(fd),
                   let object = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any],
                   (object["exitCode"] as? NSNumber)?.int32Value == 0
                {
                    output = object["stdout"] as? String ?? ""
                }
                close(fd)
            }
            if let done { DispatchQueue.main.async { done(output) } }
        }
    }

    /// Runs a command and waits for its answer, on this thread (the bar quitting).
    static func runNow(_ args: [String]) {
        guard let fd = open() else { return }
        if send(fd, args) { _ = receive(fd) }
        close(fd)
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

/// skyland's events, through its `subscribe`: workspace, focus, monitor and mode changes
/// reach the bar as they happen, with no `exec-on-workspace-change` script. The connection
/// comes back when skyland restarts.
final class SkylandEvents {
    /// (event, env with INFO)
    var onEvent: ((String, [String: String]) -> Void)?
    /// a connection was made: what was missed meanwhile can be asked for
    var onConnect: (() -> Void)?

    func start() {
        let thread = Thread { [weak self] in
            while self != nil {
                self?.listen()
                Thread.sleep(forTimeInterval: 3) // not running, or gone: try again
            }
        }
        thread.name = "skylandbar skyland events"
        thread.start()
    }

    /// Reads events until the connection ends.
    private func listen() {
        guard let fd = SkylandSocket.open() else { return }
        defer { close(fd) }
        guard SkylandSocket.send(fd, ["subscribe", "--all"]) else { return }
        DispatchQueue.main.async { [weak self] in self?.onConnect?() }
        while let message = SkylandSocket.receive(fd) {
            guard let event = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any] else { continue }
            let info = String(decoding: message, as: UTF8.self)
            let events = skylandEvent(event)
            DispatchQueue.main.async { [weak self] in
                for (name, env) in events { self?.onEvent?(name, env.merging(["INFO": info]) { a, _ in a }) }
            }
        }
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
