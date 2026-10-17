import AppKit
import SkylandBarCore

// skylandbar: a status bar for macOS that speaks sketchybar's language.
//   skylandbar                 start the bar (runs ~/.config/skylandbar/skylandbarrc, or
//                              ~/.config/sketchybar/sketchybarrc)
//   skylandbar --config <rc>   start the bar with that config
//   skylandbar --bar ... --add item ... --set ...   talk to the running bar, like sketchybar

let version = "0.8.0"
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
             --update   --reload [<file>]   --hotload on|off   --exit
    Configs and plugins written for sketchybar work as they are: scripts find this bar as
    `sketchybar` on their PATH, and the sketchybar CLI and SbarLua reach it on sketchybar's
    Mach name while sketchybar itself does not run.
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

if Client.isBarRunning() {
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
    switch ConfigFile.plan(text, environment: ProcessInfo.processInfo.environment) {
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
