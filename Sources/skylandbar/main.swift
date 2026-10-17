import AppKit
import SkylandBarCore

// skylandbar: a status bar for macOS that speaks sketchybar's language.
//   skylandbar                 start the bar (runs ~/.config/skylandbar/skylandbarrc, or
//                              ~/.config/sketchybar/sketchybarrc)
//   skylandbar --config <rc>   start the bar with that config
//   skylandbar --bar ... --add item ... --set ...   talk to the running bar, like sketchybar

let version = "0.1.0"
let usage = """
    usage: skylandbar [--config <file>]       start the bar
           skylandbar <commands>              send commands to the running bar:
             --bar <property=value>...        --add item|event|bracket|graph|slider|alias|space ...
             --set <name|/regex/> <property=value>...    --default <property=value>...
             --subscribe <name> <event>...    --trigger <event> [VAR=value...]
             --remove <name|/regex/>          --move <name> before|after <reference>
             --reorder <name>...              --rename <name> <new>   --clone <name> <parent>
             --query bar|defaults|events|displays|<name>
             --update   --reload [<file>]   --hotload on|off   --exit
    Configs and plugins written for sketchybar work as they are: scripts find this bar as
    `sketchybar` on their PATH.
    """

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--version" || arguments.first == "-v" {
    print("skylandbar \(version)")
    exit(0)
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
