import AppKit
import SkylandBarCore

// skylandbar: a status bar for macOS, skyland's.
//   skylandbar                 start the bar (~/.config/skylandbar/skylandbar.toml, else skylandbarrc)
//   skylandbar --config <file> start the bar with that config
//   skylandbar --bar ... --add item ... --set ...   talk to the running bar

let version = "0.14.0"
let usage = """
    usage: skylandbar [--config <file>]       start the bar
           skylandbar --service install|uninstall    start it at login (launchd)
           skylandbar --export                print the running bar as skylandbar.toml
           skylandbar --check [<file>]        check a skylandbar.toml (default ~/.config/skylandbar/skylandbar.toml)
           skylandbar <commands>              send commands to the running bar:
             --bar <property=value>...        --add item|event|bracket|graph|slider|alias|space|workspaces|title|notch ...
             --set <name|/regex/> <property=value>...    --default <property=value>...
             --subscribe <name> <event>...    --trigger <event> [VAR=value...]
             --remove <name|/regex/>          --move <name> before|after <reference>
             --reorder <name>...              --rename <name> <new>   --clone <name> <parent>
             --push <graph> <value>...        --animate linear|quadratic|tanh|sin|exp|circ <frames>
             --query bar|defaults|events|displays|default_menu_items|<name>
             --update   --reload [<file>]   --hotload on|off   --settings   --exit
    Its config: ~/.config/skylandbar/skylandbar.toml, else ~/.config/skylandbar/skylandbarrc (a
    script of skylandbar commands). Tools that use SketchyBar's names reach it too (README,
    Compatibility).
    """

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--version" || arguments.first == "-v" {
    print("skylandbar \(version)")
    exit(0)
}
if arguments.first == "--export" {
    exit(Client.send(["--query", "config"]))
}
if arguments.first == "--check" {
    exit(checkConfig(arguments.count >= 2 ? arguments[1] : NSHomeDirectory() + "/.config/skylandbar/skylandbar.toml"))
}
if arguments.first == "--service" {
    exit(Service.run(arguments.count == 2 ? arguments[1] : ""))
}
if arguments.first == "--help" || arguments.first == "-h" {
    print(usage)
    exit(0)
}

let startsBar = arguments.isEmpty || (arguments.count == 2 && (arguments[0] == "--config" || arguments[0] == "-c"))
guard startsBar else { exit(Client.send(arguments)) }

/// One bar per user: an exclusive lock held as long as the bar runs (the kernel lets it go
/// when the process ends, even killed). Two bars started together (skyland and a login item)
/// both passed the socket check before either listened.
let lockPath = "/tmp/skylandbar-\(NSUserName()).lock"
let lockFile = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFile < 0 || flock(lockFile, LOCK_EX | LOCK_NB) != 0 || Client.isBarRunning() {
    FileHandle.standardError.write(Data("skylandbar: already running\n".utf8))
    exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let barApp = BarApp(configPath: arguments.count == 2 ? arguments[1] : nil)
barApp.start()
application.run()

/// --check: the file's commands, run on a bar of their own (nothing on screen); its
/// problems, each with its place.
func checkConfig(_ file: String) -> Int32 {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
        print("\(file): cannot read it")
        return 1
    }
    let plan: ConfigPlan
    // as the bar runs it: includes relative to the file's directory
    var environment = ProcessInfo.processInfo.environment
    environment["CONFIG_DIR"] = URL(fileURLWithPath: file).deletingLastPathComponent().path
    switch ConfigFile.plan(text, environment: environment, read: { try? String(contentsOfFile: $0, encoding: .utf8) }) {
        case .failure(let error):
            print("\(file): \(error.message)")
            return 1
        case .success(let made): plan = made
    }
    let model = BarModel()
    var failed = false
    for step in plan.steps {
        switch CommandParser.parse(step.arguments) {
            case .failure(let error):
                print("\(step.source): [!] \(error.message)")
                failed = true
            case .success(let commands):
                let outcome = model.execute(commands)
                for problem in outcome.errors { print("\(step.source): \(problem)") }
                failed = failed || outcome.failed
        }
    }
    print(failed ? "\(file): errors above" : "\(file): ok, \(model.items.count) items")
    return failed ? 1 : 0
}
