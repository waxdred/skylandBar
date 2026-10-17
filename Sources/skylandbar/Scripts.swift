import Foundation
import SkylandBarCore

/// Runs item scripts and the config like sketchybar: `bash -c`, with NAME, SENDER, INFO...
/// and a PATH whose first directory has a `sketchybar` that is this binary, so configs and
/// plugins written for sketchybar talk to skylandbar unchanged.
final class ScriptRunner {
    var configDir: String
    /// what scripts (SbarLua above all) look the bar up by: git.felix.<barName>
    var barName = "skylandbar"
    let shimDir: String
    /// the scripts still running, stopped when the bar quits
    private var running = Set<Process>()

    init(configDir: String) {
        self.configDir = configDir
        shimDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/skylandbar/bin").path
        makeShim()
    }

    private func makeShim() {
        let manager = FileManager.default
        try? manager.createDirectory(atPath: shimDir, withIntermediateDirectories: true)
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        for name in ["sketchybar", "skylandbar"] {
            let link = "\(shimDir)/\(name)"
            if (try? manager.destinationOfSymbolicLink(atPath: link)) == binary { continue }
            try? manager.removeItem(atPath: link)
            try? manager.createSymbolicLink(atPath: link, withDestinationPath: binary)
        }
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(shimDir):\(path):/opt/homebrew/bin:/usr/local/bin"
        env["CONFIG_DIR"] = configDir
        env["BAR_NAME"] = barName
        env["SKYLANDBAR_SCRIPT"] = "1"
        return env
    }

    func run(_ runs: [ScriptRun]) {
        for run in runs {
            if !run.script.isEmpty { launch(["/bin/bash", "-c", run.script], env: run.env) }
            if !run.helper.isEmpty { MachHelpers.send(run.env, to: run.helper) }
        }
    }

    /// A file runs by itself when it is executable (its shebang), else with bash.
    @discardableResult
    func launch(file: String, onExit: (() -> Void)? = nil) -> Bool {
        let command = FileManager.default.isExecutableFile(atPath: file) ? [file] : ["/bin/bash", file]
        return launch(command, env: [:], onExit: onExit)
    }

    @discardableResult
    func launch(_ command: [String], env extra: [String: String], onExit: (() -> Void)? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        var env = environment
        for (key, value) in extra { env[key] = value }
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: configDir)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.running.remove(process)
                onExit?()
            }
        }
        do {
            try process.run()
            running.insert(process)
            return true
        } catch {
            FileHandle.standardError.write(Data("skylandbar: cannot run \(command.joined(separator: " ")): \(error)\n".utf8))
            return false
        }
    }

    func terminateAll() {
        for process in running where process.isRunning { process.terminate() }
        running = []
    }
}
