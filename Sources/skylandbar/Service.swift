import Foundation

/// `skylandbar --service install|uninstall`: a launch agent that starts the bar at login and
/// again if it crashes (not after `--exit`).
enum Service {
    static let label = "com.waxdred.skylandbar"
    static var plist: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }
    private static var domain: String { "gui/\(getuid())" }

    static func run(_ action: String) -> Int32 {
        switch action {
            case "install": return install()
            case "uninstall": return uninstall()
            default:
                FileHandle.standardError.write(Data("usage: skylandbar --service install|uninstall\n".utf8))
                return 1
        }
    }

    private static func install() -> Int32 {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        let logs = NSHomeDirectory() + "/Library/Logs/skylandbar.log"
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "EnvironmentVariables": ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
            "StandardOutPath": logs,
            "StandardErrorPath": logs,
        ]
        do {
            try FileManager.default.createDirectory(atPath: (plist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plist))
        } catch {
            FileHandle.standardError.write(Data("skylandbar: cannot write \(plist): \(error)\n".utf8))
            return 1
        }
        launchctl(["bootout", "\(domain)/\(label)"]) // an older one
        let status = launchctl(["bootstrap", domain, plist])
        print(status == 0 ? "skylandbar starts at login now (\(plist), logs in \(logs))" : "launchctl bootstrap failed (\(status))")
        return status
    }

    private static func uninstall() -> Int32 {
        launchctl(["bootout", "\(domain)/\(label)"])
        try? FileManager.default.removeItem(atPath: plist)
        print("skylandbar no longer starts at login")
        return 0
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
