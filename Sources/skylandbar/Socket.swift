import Darwin
import Foundation

// Messages between `skylandbar --...` (also as `sketchybar`, Scripts.swift) and the
// running bar: a Unix socket, the arguments NUL-separated, then the client closes its
// side; the reply is a status byte ("0" ok, "1" error) and the text to print.

enum Socket {
    static var path: String { "/tmp/skylandbar_\(NSUserName()).socket" }

    static func address() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes.prefix(buffer.count - 1))
        }
        return address
    }

    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// A connection to the running bar, nil when there is none.
    static func connectToBar() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return nil }
        noSigPipe(fd)
        var address = address()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written <= 0 { return false }
            offset += written
        }
        return true
    }

    static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0 ..< count])
        }
        return data
    }
}

enum Client {
    static func isBarRunning() -> Bool {
        guard let fd = Socket.connectToBar() else { return false }
        close(fd)
        return true
    }

    /// Sends one message, prints the reply; the exit code.
    static func send(_ arguments: [String]) -> Int32 {
        guard let fd = Socket.connectToBar() else {
            // a script the bar started, still running after it quit: nothing to say
            if ProcessInfo.processInfo.environment["SKYLANDBAR_SCRIPT"] == "1" { return 1 }
            FileHandle.standardError.write(Data("skylandbar: the bar is not running (start it with `skylandbar`)\n".utf8))
            return 1
        }
        defer { close(fd) }
        var message = Data()
        for argument in arguments {
            message.append(contentsOf: Array(argument.utf8))
            message.append(0)
        }
        guard Socket.writeAll(fd, message) else { return 1 }
        shutdown(fd, SHUT_WR)
        let reply = Socket.readAll(fd)
        guard let status = reply.first else { return 1 }
        let text = String(decoding: reply.dropFirst(), as: UTF8.self)
        if status == UInt8(ascii: "0") {
            if !text.isEmpty { FileHandle.standardOutput.write(Data(text.utf8)) }
            return 0
        }
        FileHandle.standardError.write(Data(text.utf8))
        return 1
    }
}

/// Listens on the socket on its own thread; each message is handled on the main thread.
final class Server {
    private let handle: ([String]) -> (ok: Bool, text: String)
    private var fd: Int32 = -1
    /// the socket file this bar made: on quit it removes only that one, not a newer bar's
    private var inode: ino_t = 0

    init(handle: @escaping ([String]) -> (ok: Bool, text: String)) {
        self.handle = handle
    }

    func start() -> Bool {
        unlink(Socket.path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = Socket.address()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 64) == 0 else { return false }
        var info = stat()
        if stat(Socket.path, &info) == 0 { inode = info.st_ino }
        let listener = fd, handle = self.handle
        let thread = Thread {
            // a pool per message: this thread never goes back to a run loop, and what each
            // message autoreleased stayed for good (the bar grew by its scripts' --set calls)
            while true { autoreleasepool {
                let client = accept(listener, nil, nil)
                if client < 0 { return }
                Socket.noSigPipe(client)
                let data = Socket.readAll(client)
                var arguments = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
                if arguments.last == "" { arguments.removeLast() }
                var reply: (ok: Bool, text: String) = (false, "")
                DispatchQueue.main.sync { reply = handle(arguments) }
                var out = Data((reply.ok ? "0" : "1").utf8)
                out.append(Data(reply.text.utf8))
                _ = Socket.writeAll(client, out)
                close(client)
            } }
        }
        thread.name = "skylandbar socket"
        thread.start()
        return true
    }

    func stop() {
        if fd >= 0 { close(fd) }
        var info = stat()
        if stat(Socket.path, &info) == 0, info.st_ino == inode { unlink(Socket.path) }
    }
}
