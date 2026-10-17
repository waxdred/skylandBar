import AppKit
import SkylandBarCore
import SwiftUI

// `skylandbar --settings` (the notch's gear, for one): the bar's settings as sliders and pickers,
// in skyland's settings window style (its theme's colors over a blurred window). The values are
// the running bar's (a theme's included); changes wait for Save (⌘S), which checks the config,
// writes each changed value on its own line of the config file (comments kept, TOMLLines), and
// loads it again. "Open config file" gives the whole file to its editor.

struct SettingField: Identifiable {
    enum Kind {
        case number(ClosedRange<Double>, step: Double, unit: String)
        case choice([String])
    }

    /// where it is written: `[bar]`, or the inline `notch = { ... }` / `workspaces = { ... }`
    /// table of the notch's or the workspaces component's item
    enum Place { case bar, notch, workspaces }

    let place: Place
    let key: String
    let label: String
    let kind: Kind
    /// shown when neither the bar nor the file has it
    var fallback = ""
    var id: String { "\(place).\(key)" }
}

private let settingGroups: [(title: String, fields: [SettingField])] = [
    ("Bar", [
        SettingField(place: .bar, key: "position", label: "Position", kind: .choice(["top", "bottom"])),
        SettingField(place: .bar, key: "height", label: "Height", kind: .number(16 ... 64, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "y_offset", label: "Offset from the edge", kind: .number(0 ... 30, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "margin", label: "Side margin", kind: .number(0 ... 60, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "padding_left", label: "Padding left", kind: .number(0 ... 40, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "padding_right", label: "Padding right", kind: .number(0 ... 40, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "corner_radius", label: "Corner radius", kind: .number(0 ... 30, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "topmost", label: "Above windows", kind: .choice(["off", "window", "on"])),
    ]),
    ("Glass", [
        SettingField(place: .bar, key: "glass_engine", label: "Engine", kind: .choice(["auto", "system", "metal", "backdrop"])),
        SettingField(place: .bar, key: "glass_refraction", label: "Refraction", kind: .number(0 ... 10, step: 0.5, unit: "pt")),
        SettingField(place: .bar, key: "glass_blur", label: "Blur", kind: .number(0 ... 12, step: 0.5, unit: "pt")),
        SettingField(place: .bar, key: "glass_saturation", label: "Saturation", kind: .number(0.5 ... 3, step: 0.1, unit: "x")),
        SettingField(place: .bar, key: "glass_spacing", label: "Shapes melt within", kind: .number(0 ... 40, step: 1, unit: "pt")),
        SettingField(place: .bar, key: "motion", label: "Animations", kind: .choice(["auto", "full", "reduced"])),
    ]),
    ("Workspaces", [
        SettingField(place: .workspaces, key: "max", label: "At most (0: all)", kind: .number(0 ... 30, step: 1, unit: ""), fallback: "0"),
        SettingField(place: .workspaces, key: "animation", label: "Animation", kind: .choice(["linear", "quadratic", "tanh", "sin", "exp", "circ"]), fallback: "tanh"),
    ]),
    ("Notch, open", [
        SettingField(place: .notch, key: "glass", label: "Material", kind: .choice(["regular", "clear", "off"]), fallback: "off"),
        SettingField(place: .notch, key: "width", label: "Width", kind: .number(200 ... 900, step: 5, unit: "pt"), fallback: "0"),
        SettingField(place: .notch, key: "height", label: "Height", kind: .number(60 ... 400, step: 5, unit: "pt"), fallback: "0"),
        SettingField(place: .notch, key: "padding", label: "Padding", kind: .number(0 ... 40, step: 1, unit: "pt"), fallback: "12"),
        SettingField(place: .notch, key: "corner_radius", label: "Bottom corners", kind: .number(0 ... 40, step: 1, unit: "pt"), fallback: "24"),
        SettingField(place: .notch, key: "flare", label: "Top curves", kind: .number(0 ... 30, step: 1, unit: "pt"), fallback: "19"),
        SettingField(place: .notch, key: "open_delay", label: "Opens after", kind: .number(0 ... 1, step: 0.05, unit: "s"), fallback: "0.3"),
        SettingField(place: .notch, key: "close_delay", label: "Closes after", kind: .number(0 ... 1, step: 0.05, unit: "s"), fallback: "0.1"),
    ]),
    ("Notch, closed", [
        SettingField(place: .notch, key: "closed_width", label: "Width", kind: .number(100 ... 400, step: 1, unit: "pt"), fallback: "185"),
        SettingField(place: .notch, key: "closed_height", label: "Height", kind: .number(20 ... 80, step: 1, unit: "pt"), fallback: "32"),
        SettingField(place: .notch, key: "closed_corner_radius", label: "Bottom corners", kind: .number(0 ... 30, step: 1, unit: "pt"), fallback: "14"),
        SettingField(place: .notch, key: "closed_flare", label: "Top curves", kind: .number(0 ... 20, step: 1, unit: "pt"), fallback: "6"),
    ]),
]

/// skyland's theme colors (~/.cache/skyland/theme.env), the system's without skyland.
struct SettingsColors {
    var accent = Color.accentColor, background = Color.black, text = Color.primary, dim = Color.secondary

    static func current() -> SettingsColors {
        let env = (try? String(contentsOfFile: NSHomeDirectory() + "/.cache/skyland/theme.env", encoding: .utf8)) ?? ""
        var values: [String: Color] = [:]
        for line in env.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let color = ARGB.parse(parts[1]) { values[parts[0]] = Color(nsColor: Fonts.color(color)) }
        }
        var result = SettingsColors()
        if let accent = values["ACCENT"] { result.accent = accent }
        if let background = values["BAR_BG"] { result.background = background }
        if let text = values["TEXT"] { result.text = text }
        if let dim = values["TEXT_DIM"] { result.dim = dim }
        return result
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    /// raw TOML values by field id (`8`, `"metal"`), as shown, saved or not
    @Published var values: [String: String] = [:]
    /// changes not written yet: Save writes them all at once
    @Published var pending: [String: String] = [:]
    @Published var error: String?
    @Published var saved = false
    @Published var colors = SettingsColors()

    let file: String
    /// the running bar's values: `[bar]` keys, and each component's name and options by place
    private let current: () -> (bar: [String: String], components: [SettingField.Place: (name: String, options: [String: String])])
    /// checks a config's text: nil when it loads, else why not
    private let check: (String) -> String?
    private let reloaded: () -> Void

    init(file: String, current: @escaping () -> (bar: [String: String], components: [SettingField.Place: (name: String, options: [String: String])]),
         check: @escaping (String) -> String?, reloaded: @escaping () -> Void)
    {
        self.file = file
        self.current = current
        self.check = check
        self.reloaded = reloaded
        load()
    }

    /// a place's fields show when the bar has it
    func has(_ place: SettingField.Place) -> Bool { place == .bar || current().components[place] != nil }

    /// The bar's values; drops unsaved changes (Revert).
    func load() {
        let now = current()
        for field in settingGroups.flatMap(\.fields) {
            let raw = field.place == .bar ? now.bar[field.key] : now.components[field.place]?.options[field.key]
            values[field.id] = raw ?? field.fallback
        }
        pending = [:]
        error = nil
        colors = .current()
    }

    func set(_ field: SettingField, _ raw: String) {
        values[field.id] = raw
        pending[field.id] = raw
        saved = false
    }

    func save() {
        guard !pending.isEmpty else { return }
        guard var text = try? String(contentsOfFile: file, encoding: .utf8) else { error = "cannot read \(file)"; return }
        let components = current().components
        for field in settingGroups.flatMap(\.fields) {
            guard let raw = pending[field.id] else { continue }
            let value: String
            if case .choice = field.kind { value = "\"\(raw)\"" } else { value = raw }
            switch field.place {
                case .bar:
                    text = TOMLLines.set(text, section: "bar", key: field.key, value: value)
                case .notch, .workspaces:
                    let table = field.place == .notch ? "notch" : "workspaces"
                    guard let item = components[field.place]?.name,
                          let changed = TOMLLines.setInline(text, item: item, table: table, field: field.key, value: value) else {
                        error = "no `\(table) = { ... }` line in its [[item]] to write \(field.key) in"
                        return
                    }
                    text = changed
            }
        }
        if let problem = check(text) { error = "Not saved: \(problem)"; return }
        do {
            try text.write(toFile: file, atomically: true, encoding: .utf8)
        } catch {
            self.error = "cannot write \(file): \(error.localizedDescription)"
            return
        }
        error = nil
        pending = [:]
        saved = true
        reloaded()
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle").font(.system(size: 26, weight: .semibold)).foregroundStyle(model.colors.accent)
                Text("skylandbar").font(.system(.title2, design: .monospaced).weight(.bold)).foregroundStyle(model.colors.accent)
            }
            .padding(.top, 26) // under the transparent title bar
            Form {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }
                Section {
                    HStack {
                        Text((model.file as NSString).abbreviatingWithTildeInPath)
                            .font(.system(.callout, design: .monospaced)).foregroundStyle(model.colors.dim)
                        Spacer()
                        Button("Open config file") { NSWorkspace.shared.open(URL(fileURLWithPath: model.file)) }
                    }
                } header: { SectionHeader(title: "File", colors: model.colors) }
                ForEach(settingGroups.filter { model.has($0.fields[0].place) }, id: \.title) { group in
                    Section {
                        ForEach(group.fields) { field in row(field) }
                    } header: { SectionHeader(title: group.title, colors: model.colors) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .frame(minWidth: 560, minHeight: 520)
        .tint(model.colors.accent)
        .background(model.colors.background.opacity(0.8)) // the theme over the window's blur
        .preferredColorScheme(.dark)
    }

    /// Unsaved changes, Revert, Save (⌘S)
    private var saveBar: some View {
        HStack(spacing: 12) {
            let count = model.pending.count
            Text(count > 0 ? "\(count) unsaved change\(count > 1 ? "s" : "")" : model.saved ? "saved" : "")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(count > 0 ? model.colors.accent : model.colors.dim)
            Spacer()
            Button("Revert") { model.load() }
                .disabled(count == 0)
            Button("Save") { model.save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func row(_ field: SettingField) -> some View {
        let raw = model.values[field.id] ?? ""
        let changed = model.pending[field.id] != nil
        let label = Text(field.label).foregroundStyle(changed ? model.colors.accent : model.colors.text)
        switch field.kind {
            case .number(let range, let step, let unit):
                let value = Double(raw) ?? range.lowerBound
                HStack {
                    label
                    Slider(
                        // no `step:`, it draws a tick per step; rounded to the step instead
                        value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: {
                            let rounded = ($0 / step).rounded() * step
                            if rounded != value { model.set(field, Self.format(rounded, step)) }
                        }),
                        in: range
                    )
                    Text(Self.format(value, step) + unit).font(.system(.body, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(model.colors.dim).frame(width: 70, alignment: .trailing)
                }
            case .choice(let options):
                Picker(selection: Binding(get: { TOMLLines.unquote(raw) }, set: { model.set(field, $0) })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                } label: { label }
        }
    }

    /// 12, 0.5, 1.5: as few decimals as the step needs
    static func format(_ value: Double, _ step: Double) -> String {
        step >= 1 ? String(Int(value.rounded())) : String(format: step >= 0.1 ? "%.1f" : "%.2f", value)
    }
}

/// `// BAR` section header in the theme's accent, as skyland's.
private struct SectionHeader: View {
    let title: String
    let colors: SettingsColors
    var body: some View {
        Text("// " + title.uppercased())
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(colors.accent)
            .kerning(1.2)
    }
}

/// The settings window: made once, shown again (a second `--settings` on it closes it).
@MainActor
final class SettingsWindow {
    private let window: NSWindow
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "skylandbar settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let host = NSHostingView(rootView: SettingsView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        window.contentView = blur
    }

    func toggle() {
        if window.isVisible, window.isKeyWindow { return window.close() }
        if !window.isVisible { model.load() } // the file or the bar may have changed meanwhile
        // on the screen under the mouse; orderFrontRegardless: an accessory app's activate can be ignored
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2, y: screen.visibleFrame.midY - window.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
