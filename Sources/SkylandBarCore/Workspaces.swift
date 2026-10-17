import Foundation

// skyland's (or AeroSpace's) workspaces and focused window, as the bar's built-in
// components draw them: `--add workspaces <name> <position>` (an item per workspace) and
// `--add title <name> <position>` (the focused window). The app asks skyland with
// `list-workspaces` / `list-windows --json` and hands the answers to `SkylandData`.

public struct WorkspaceInfo: Equatable {
    public var name: String
    /// 1-based, NSScreen order (skyland's monitor-appkit-nsscreen-screens-id)
    public var display: Int
    public var focused: Bool
    public var visible: Bool
    /// the apps of its windows, one entry per window
    public var apps: [String]

    public init(name: String, display: Int, focused: Bool, visible: Bool, apps: [String] = []) {
        self.name = name
        self.display = display
        self.focused = focused
        self.visible = visible
        self.apps = apps
    }
}

public struct FocusedWindow: Equatable {
    public var app: String
    public var bundleId: String
    public var title: String

    public init(app: String, bundleId: String, title: String) {
        self.app = app
        self.bundleId = bundleId
        self.title = title
    }
}

public enum SkylandData {
    /// What the app asks skyland.
    public static let workspacesCommand = ["list-workspaces", "--all", "--json", "--format",
                                           "%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-appkit-nsscreen-screens-id}"]
    public static let windowsCommand = ["list-windows", "--all", "--json", "--format", "%{workspace} %{app-name}"]
    public static let focusedCommand = ["list-windows", "--focused", "--json", "--format", "%{app-name} %{app-bundle-id} %{window-title}"]

    private static func objects(_ json: String) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] ?? []
    }

    private static func text(_ value: Any?) -> String {
        switch value {
            case let string as String: return string
            case let number as NSNumber: return number.stringValue
            default: return ""
        }
    }

    private static func flag(_ value: Any?) -> Bool {
        switch value {
            case let bool as Bool: return bool
            case let string as String: return string == "true"
            default: return false
        }
    }

    /// The workspaces, in skyland's order, with the apps of their windows.
    public static func workspaces(_ workspacesJSON: String, windows windowsJSON: String) -> [WorkspaceInfo] {
        var apps: [String: [String]] = [:]
        for window in objects(windowsJSON) { apps[text(window["workspace"]), default: []].append(text(window["app-name"])) }
        return objects(workspacesJSON).map { object in
            let name = text(object["workspace"])
            return WorkspaceInfo(name: name, display: Int(text(object["monitor-appkit-nsscreen-screens-id"])) ?? 1,
                                 focused: flag(object["workspace-is-focused"]), visible: flag(object["workspace-is-visible"]),
                                 apps: apps[name] ?? [])
        }
    }

    /// The focused window, nil when there is none (an empty workspace).
    public static func focusedWindow(_ json: String) -> FocusedWindow? {
        guard let object = objects(json).first else { return nil }
        return FocusedWindow(app: text(object["app-name"]), bundleId: text(object["app-bundle-id"]), title: text(object["window-title"]))
    }
}

/// The states a workspace item is styled by, after the component's own properties: `empty`
/// (no window), `visible` (shown on a display), `focused`; the later ones win.
public let workspaceStates = ["empty", "visible", "focused"]

extension WorkspaceInfo {
    func isIn(_ state: String) -> Bool {
        switch state {
            case "empty": return apps.isEmpty
            case "visible": return visible
            case "focused": return focused
            default: return false
        }
    }

    /// `{name}`, `{apps}` (each app once, in order) and `{count}` (windows) in a text.
    func fill(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var seen = Set<String>()
        let unique = apps.filter { seen.insert($0).inserted }
        return text.replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{apps}", with: unique.joined(separator: " "))
            .replacingOccurrences(of: "{count}", with: String(apps.count))
    }
}
