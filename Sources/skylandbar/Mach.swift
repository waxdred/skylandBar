import Foundation
import SkylandBarCore
import SkylandMach

/// The bar on sketchybar's Mach names, for the sketchybar CLI and SbarLua: git.felix.skylandbar
/// always, git.felix.sketchybar too when sketchybar does not run. Each message is handled
/// on the main thread, like the socket's, and answered with its output.
final class MachServer {
    /// the names registered (without git.felix.)
    private(set) var names: [String] = []
    private let handle: ([String]) -> (ok: Bool, text: String)

    init(handle: @escaping ([String]) -> (ok: Bool, text: String)) {
        self.handle = handle
    }

    func start() {
        let port = skyland_mach_port()
        guard port != 0 else { return }
        names = ["skylandbar", "sketchybar"].filter { skyland_mach_register(port, "git.felix.\($0)") }
        if !names.contains("sketchybar") {
            FileHandle.standardError.write(Data("skylandbar: git.felix.sketchybar is taken (sketchybar runs?): the sketchybar CLI and SbarLua will talk to it, not to skylandbar\n".utf8))
        }
        guard !names.isEmpty else { return }
        let handle = self.handle
        let thread = Thread {
            while true {
                var data: UnsafeMutablePointer<CChar>? = nil
                var length: UInt32 = 0
                var reply: UInt32 = 0
                guard skyland_mach_receive(port, &data, &length, &reply) else { continue }
                var bytes: [UInt8] = []
                if let data {
                    bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: Int(length)))
                    free(data)
                }
                let arguments = Wire.arguments(bytes)
                var answer: (ok: Bool, text: String) = (true, "")
                if !arguments.isEmpty { DispatchQueue.main.sync { answer = handle(arguments) } }
                guard reply != 0 else { continue }
                // the CLI prints the answer, a NUL-ended string; "[!]..." is an error
                var text = Array(answer.text.utf8)
                text.append(0)
                text.withUnsafeBufferPointer { buffer in
                    buffer.withMemoryRebound(to: CChar.self) { _ = skyland_mach_send(reply, $0.baseAddress, UInt32($0.count)) }
                }
                skyland_mach_release(reply)
            }
        }
        thread.name = "skylandbar mach"
        thread.start()
    }
}

/// Events sent to mach_helpers (SbarLua's event loop, helper programs), by bootstrap name.
enum MachHelpers {
    private static var ports: [String: UInt32] = [:]

    static func send(_ env: [String: String], to name: String) {
        var port = ports[name] ?? 0
        if port == 0 {
            port = skyland_mach_look_up(name)
            guard port != 0 else { return }
            ports[name] = port
        }
        let message = Wire.event(env)
        let sent = message.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { skyland_mach_send(port, $0.baseAddress, UInt32($0.count)) }
        }
        if !sent { // gone (the Lua config restarted): looked up again next time
            skyland_mach_release(port)
            ports[name] = nil
        }
    }
}
