import Foundation

// The properties of the bar and of its items, their names and defaults. Each `apply` takes
// the part of
// the key after its own prefix ("background.color" -> background.apply("color", ...)) and
// returns an error message, or nil when the value was taken.

public struct ShadowProps: Equatable {
    public var drawing = false
    public var color = ARGB.black
    public var angle = 30.0
    public var distance = 5.0

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "drawing": return Value.setBool(&drawing, value)
            case "color": return Value.setColor(&color, value, part: rest)
            case "angle": return Value.setNumber(&angle, value)
            case "distance": return Value.setNumber(&distance, value)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        ["drawing": drawing ? "on" : "off", "color": color.description, "angle": angle, "distance": distance]
    }
}

/// An image drawn in a background: a file, `app.<bundle id or name>` (its icon) or
/// `media.artwork` (the now playing artwork).
public struct ImageProps: Equatable {
    public var string = ""
    public var drawing = true
    public var scale = 1.0
    public var cornerRadius = 0.0
    public var borderWidth = 0.0
    public var borderColor = ARGB.clear
    public var paddingLeft = 0.0
    public var paddingRight = 0.0
    public var yOffset = 0.0
    public var shadow = ShadowProps()

    public init() {}

    public var isShown: Bool { drawing && !string.isEmpty }

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "string":
                string = value
                return nil
            case "drawing": return Value.setBool(&drawing, value)
            case "scale": return Value.setNumber(&scale, value, minimum: 0)
            case "corner_radius": return Value.setNumber(&cornerRadius, value, minimum: 0)
            case "border_width": return Value.setNumber(&borderWidth, value, minimum: 0)
            case "border_color": return Value.setColor(&borderColor, value, part: rest)
            case "padding_left": return Value.setNumber(&paddingLeft, value)
            case "padding_right": return Value.setNumber(&paddingRight, value)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "shadow": return rest.map { shadow.apply($0, value) } ?? Value.setBool(&shadow.drawing, value)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        [
            "value": string, "drawing": drawing ? "on" : "off", "scale": scale, "corner_radius": cornerRadius,
            "border_width": borderWidth, "border_color": borderColor.description,
            "padding_left": paddingLeft, "padding_right": paddingRight, "y_offset": yOffset, "shadow": shadow.json,
        ]
    }
}

public struct BackgroundProps: Equatable {
    public var drawing = false
    public var color = ARGB.clear
    public var borderColor = ARGB.clear
    public var borderWidth = 0.0
    public var height = 0.0 // 0: the bar's height
    /// `concentric` (-1): its container's radius less the gap between them (Apple's concentric
    /// corners); on a glass background, 0 is a capsule (Liquid Glass's default shape)
    public var cornerRadius = 0.0
    public var paddingLeft = 0.0
    public var paddingRight = 0.0
    public var xOffset = 0.0
    public var yOffset = 0.0
    public var clip = 0.0
    public var image = ImageProps()
    public var shadow = ShadowProps()
    /// skylandbar: Liquid Glass (macOS 26) tinted with `color`: off | regular | clear
    public var glass = "off"

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "drawing": return Value.setBool(&drawing, value)
            // giving a background a color, a border or an image draws it
            case "color": return enable(Value.setColor(&color, value, part: rest))
            case "border_color": return enable(Value.setColor(&borderColor, value, part: rest))
            case "border_width": return Value.setNumber(&borderWidth, value, minimum: 0)
            case "height": return Value.setNumber(&height, value, minimum: 0)
            case "corner_radius":
                if value == "concentric" {
                    cornerRadius = -1
                    return nil
                }
                return Value.setNumber(&cornerRadius, value, minimum: 0)
            case "padding_left": return Value.setNumber(&paddingLeft, value)
            case "padding_right": return Value.setNumber(&paddingRight, value)
            case "x_offset": return Value.setNumber(&xOffset, value)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "clip": return Value.setNumber(&clip, value, minimum: 0)
            case "image":
                guard let rest else {
                    image.string = value
                    return enable(nil)
                }
                return image.apply(rest, value)
            case "shadow": return rest.map { shadow.apply($0, value) } ?? Value.setBool(&shadow.drawing, value)
            case "glass": return Value.setGlass(&glass, value)
            default: return unknownProperty
        }
    }

    private mutating func enable(_ error: String?) -> String? {
        if error == nil { drawing = true }
        return error
    }

    public var json: [String: Any] {
        [
            "drawing": drawing ? "on" : "off", "color": color.description, "border_color": borderColor.description,
            "border_width": borderWidth, "height": height, "corner_radius": cornerRadius < 0 ? "concentric" as Any : cornerRadius,
            "padding_left": paddingLeft, "padding_right": paddingRight, "x_offset": xOffset, "y_offset": yOffset,
            "clip": clip, "image": image.json, "shadow": shadow.json, "glass": glass,
        ]
    }
}

/// The icon or the label of an item.
public struct TextProps: Equatable {
    public var drawing = true
    public var highlight = false
    public var string = ""
    public var color = ARGB.white
    public var highlightColor = ARGB.black
    public var paddingLeft = 0.0
    public var paddingRight = 0.0
    public var yOffset = 0.0
    public var font = FontSpec.standard
    /// nil: as wide as the text
    public var width: Double? = nil
    public var align = "left"
    public var maxChars = 0
    public var scrollDuration = 100.0
    public var background = BackgroundProps()
    public var shadow = ShadowProps()

    public init() {}

    /// The text as drawn: `max_chars` cut.
    public var shown: String {
        maxChars > 0 && string.count > maxChars ? String(string.prefix(maxChars)) : string
    }

    /// Whether `scroll_texts` moves it: longer than `max_chars`.
    public var scrolls: Bool { maxChars > 0 && string.count > maxChars }

    /// With `scroll_texts`: the `max_chars` characters `step` characters into the text,
    /// which loops with three spaces between the end and the start.
    public func scrolled(_ step: Int) -> String {
        guard scrolls else { return shown }
        let loop = Array(string + "   ")
        let start = step % loop.count
        return String((0 ..< maxChars).map { loop[(start + $0) % loop.count] })
    }

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "drawing": return Value.setBool(&drawing, value)
            case "highlight": return Value.setBool(&highlight, value)
            case "string":
                string = value
                return nil
            case "color": return Value.setColor(&color, value, part: rest)
            case "highlight_color": return Value.setColor(&highlightColor, value, part: rest)
            case "padding_left": return Value.setNumber(&paddingLeft, value)
            case "padding_right": return Value.setNumber(&paddingRight, value)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "font":
                switch rest {
                    case nil:
                        guard let parsed = FontSpec.parse(value, base: font) else { return "'\(value)' is not a font (Family:Style:Size)" }
                        font = parsed
                        return nil
                    case "family"?:
                        font.family = value
                        return nil
                    case "style"?:
                        font.style = value
                        return nil
                    case "size"?:
                        return Value.setNumber(&font.size, value, minimum: 1)
                    default:
                        return unknownProperty
                }
            case "width":
                if value == "dynamic" {
                    width = nil
                    return nil
                }
                var fixed = 0.0
                if let error = Value.setNumber(&fixed, value, minimum: 0) { return error }
                width = fixed
                return nil
            case "align": return Value.oneOf(&align, value, ["left", "center", "right"])
            case "max_chars":
                guard let count = Int(value), count >= 0 else { return "'\(value)' is not a count" }
                maxChars = count
                return nil
            case "scroll_duration": return Value.setNumber(&scrollDuration, value, minimum: 0)
            case "background": return rest.map { background.apply($0, value) } ?? unknownProperty
            case "shadow": return rest.map { shadow.apply($0, value) } ?? Value.setBool(&shadow.drawing, value)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        [
            "drawing": drawing ? "on" : "off", "highlight": highlight ? "on" : "off", "value": string,
            "color": color.description, "highlight_color": highlightColor.description,
            "padding_left": paddingLeft, "padding_right": paddingRight, "y_offset": yOffset,
            "font": font.description, "width": width.map { $0 as Any } ?? "dynamic", "align": align,
            "max_chars": maxChars, "scroll_duration": scrollDuration,
            "background": background.json, "shadow": shadow.json,
        ]
    }
}

public let itemPositions = ["left", "right", "center", "q", "e"]

public struct ItemProps: Equatable {
    public var drawing = true
    public var position = "left"
    /// all | active | a list of display numbers "1,2"
    public var display = "all"
    /// macOS Spaces the item is shown on: all | "1,2" (kept for configs, skyland has its own workspaces)
    public var space = "all"
    public var ignoreAssociation = false
    public var yOffset = 0.0
    /// nil: as wide as its icon and label
    public var width: Double? = nil
    public var blurRadius = 0.0
    public var scrollTexts = false
    public var script = ""
    public var clickScript = ""
    /// seconds between `routine` updates, 0: none
    public var updateFreq = 0.0
    /// on | off | when_shown
    public var updates = "when_shown"
    public var icon = TextProps()
    public var label = TextProps()
    public var background = BackgroundProps()
    public var popup = PopupProps()
    public var graph = GraphProps()
    public var slider = SliderProps()
    public var alias = AliasProps()
    /// a program's bootstrap name (SbarLua's, a helper's): it gets the item's events as a
    /// Mach message instead of (or as well as) a script
    public var machHelper = ""
    /// shadow...: taken so configs load, not used
    public var extra: [String: String] = [:]

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "icon", "label":
                guard let rest else {
                    if head == "icon" { icon.string = value } else { label.string = value }
                    return nil
                }
                return head == "icon" ? icon.apply(rest, value) : label.apply(rest, value)
            case "drawing": return Value.setBool(&drawing, value)
            case "position":
                guard itemPositions.contains(value) || value.hasPrefix("popup.") else {
                    return "'\(value)' is not one of \(itemPositions.joined(separator: ", ")) or popup.<item>"
                }
                position = value
                return nil
            case "display", "associated_display":
                guard value == "all" || value == "active" || Self.isNumberList(value) else { return "'\(value)' is not all, active or display numbers" }
                display = value
                return nil
            case "space", "associated_space":
                guard value == "all" || Self.isNumberList(value) else { return "'\(value)' is not all or space numbers" }
                space = value
                return nil
            case "ignore_association": return Value.setBool(&ignoreAssociation, value)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "width":
                if value == "dynamic" {
                    width = nil
                    return nil
                }
                var fixed = 0.0
                if let error = Value.setNumber(&fixed, value, minimum: 0) { return error }
                width = fixed
                return nil
            case "blur_radius": return Value.setNumber(&blurRadius, value, minimum: 0)
            case "scroll_texts": return Value.setBool(&scrollTexts, value)
            case "script":
                script = value
                return nil
            case "click_script":
                clickScript = value
                return nil
            case "update_freq": return Value.setNumber(&updateFreq, value, minimum: 0)
            case "updates":
                if value == "when_shown" {
                    updates = value
                    return nil
                }
                var on = updates != "off"
                if let error = Value.setBool(&on, value) { return error }
                updates = on ? "on" : "off"
                return nil
            case "background": return rest.map { background.apply($0, value) } ?? unknownProperty
            case "popup": return rest.map { popup.apply($0, value) } ?? unknownProperty
            case "graph": return rest.map { graph.apply($0, value) } ?? unknownProperty
            case "slider": return rest.map { slider.apply($0, value) } ?? unknownProperty
            case "alias": return rest.map { alias.apply($0, value) } ?? unknownProperty
            case "mach_helper", "event_port":
                machHelper = value
                return nil
            case "shadow":
                extra[key] = value
                return nil
            default: return unknownProperty
        }
    }

    /// Whether events do anything for it: a script or a mach_helper.
    public var hasScript: Bool { !script.isEmpty || !machHelper.isEmpty }

    static func isNumberList(_ value: String) -> Bool {
        !value.isEmpty && value.split(separator: ",").allSatisfy { Int($0) != nil }
    }

    /// Whether the item goes on the bar of display `number` (1-based, NSScreen order);
    /// `active` is the display with the focus.
    public func isShown(onDisplay number: Int, activeDisplay: Int) -> Bool {
        switch display {
            case "all": return true
            case "active": return number == activeDisplay
            default: return display.split(separator: ",").compactMap { Int($0) }.contains(number)
        }
    }

    public var json: [String: Any] {
        [
            "drawing": drawing ? "on" : "off", "position": position, "associated_display": display, "associated_space": space,
            "ignore_association": ignoreAssociation ? "on" : "off", "y_offset": yOffset,
            "width": width.map { $0 as Any } ?? "dynamic", "blur_radius": blurRadius, "scroll_texts": scrollTexts ? "on" : "off",
            "background": background.json,
        ]
    }

    /// Whether the item goes on the bar while these Mission Control spaces are shown
    /// (`space` lists them; `all` or `ignore_association`: always).
    public func isShown(onSpaces current: [Int]) -> Bool {
        if space == "all" || ignoreAssociation || current.isEmpty { return true }
        return space.split(separator: ",").compactMap { Int($0) }.contains { current.contains($0) }
    }
}

/// The items with `position=popup.<this item>`, in a window under (or over) the item.
public struct PopupProps: Equatable {
    public var drawing = false
    public var horizontal = false
    public var topmost = true
    /// the height of each row, 0: the bar's height
    public var height = 0.0
    public var blurRadius = 0.0
    public var yOffset = 0.0
    /// left | center | right, against the item
    public var align = "left"
    public var background = BackgroundProps()

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "drawing": return Value.setBool(&drawing, value)
            case "horizontal": return Value.setBool(&horizontal, value)
            case "topmost": return Value.setBool(&topmost, value)
            case "height": return Value.setNumber(&height, value, minimum: 0)
            case "blur_radius": return Value.setNumber(&blurRadius, value, minimum: 0)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "align": return Value.oneOf(&align, value, ["left", "center", "right"])
            case "background": return rest.map { background.apply($0, value) } ?? unknownProperty
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        [
            "drawing": drawing ? "on" : "off", "horizontal": horizontal ? "on" : "off", "topmost": topmost ? "on" : "off",
            "height": height, "blur_radius": blurRadius, "y_offset": yOffset, "align": align, "background": background.json,
        ]
    }
}

/// `--add graph <name> <position> <width>`: values from 0 to 1 given with `--push`, the
/// newest on the right, one point each.
public struct GraphProps: Equatable {
    public var width = 0.0
    public var color = ARGB(0xCCCC_CCCC)
    /// nil: `color` at a third of its opacity
    public var fillColor: ARGB? = nil
    public var lineWidth = 0.5

    public init() {}

    public var fill: ARGB { fillColor ?? color.withAlpha(color.alpha / 3) }

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "color": return Value.setColor(&color, value, part: rest)
            case "fill_color":
                var fill = self.fill
                if let error = Value.setColor(&fill, value, part: rest) { return error }
                fillColor = fill
                return nil
            case "line_width": return Value.setNumber(&lineWidth, value, minimum: 0)
            case "width": return Value.setNumber(&width, value, minimum: 0)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        ["width": width, "color": color.description, "fill_color": fill.description, "line_width": lineWidth]
    }
}

/// `--add slider <name> <position> <width>`: a track (`slider.background`), its filled
/// part (`slider.highlight_color`) and a knob (a text); dragging it sends `mouse.clicked`
/// with PERCENTAGE.
public struct SliderProps: Equatable {
    public var width = 0.0
    public var percentage = 0.0
    public var highlightColor = ARGB(0xFF00_00FF)
    public var background = BackgroundProps()
    public var knob = TextProps()

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "percentage":
                var percent = percentage
                if let error = Value.setNumber(&percent, value) { return error }
                percentage = min(100, max(0, percent))
                return nil
            case "highlight_color": return Value.setColor(&highlightColor, value, part: rest)
            case "width": return Value.setNumber(&width, value, minimum: 0)
            case "background": return rest.map { background.apply($0, value) } ?? unknownProperty
            case "knob":
                guard let rest else {
                    knob.string = value
                    return nil
                }
                return knob.apply(rest, value)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] {
        [
            "width": width, "percentage": percentage, "highlight_color": highlightColor.description,
            "background": background.json, "knob": knob.json,
        ]
    }
}

/// `--add alias "<application>,<item>" <position>`: a copy of a menu bar item.
public struct AliasProps: Equatable {
    /// a tint, clear: the item's own colors
    public var color = ARGB.clear
    public var scale = 1.0
    /// seconds between captures
    public var updateFreq = 1.0

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "color": return Value.setColor(&color, value, part: rest)
            case "scale": return Value.setNumber(&scale, value, minimum: 0)
            case "update_freq": return Value.setNumber(&updateFreq, value, minimum: 0.1)
            default: return unknownProperty
        }
    }

    public var json: [String: Any] { ["color": color.description, "scale": scale, "update_freq": updateFreq] }
}

public struct BarProps: Equatable {
    public var color = ARGB(0x4400_0000)
    public var borderColor = ARGB(0xFFFF_0000)
    public var borderWidth = 0.0
    /// top | bottom
    public var position = "top"
    public var height = 25.0
    /// height on displays with a notch, 0: `height`
    public var notchDisplayHeight = 0.0
    public var margin = 0.0
    public var yOffset = 0.0
    public var cornerRadius = 0.0
    public var blurRadius = 0.0
    public var paddingLeft = 0.0
    public var paddingRight = 0.0
    public var notchWidth = 200.0
    public var notchOffset = 0.0
    /// main | all | display numbers "1,2"
    public var display = "all"
    /// on | off | current
    public var hidden = "off"
    /// on | off | window
    public var topmost = "off"
    public var sticky = true
    public var fontSmoothing = false
    public var shadow = false
    /// skylandbar: Liquid Glass (macOS 26) tinted with `color`: off | regular | clear
    public var glass = "off"
    /// how close glass backgrounds get before they merge into one shape
    /// (NSGlassEffectContainerView's spacing); 0: they never merge
    public var glassSpacing = 0.0
    /// who draws the glass: auto (system on macOS 26, else metal with Screen Recording, else
    /// backdrop), system (NSGlassEffectView), metal (skylandbar's shader: refraction, rim
    /// light), backdrop (Core Animation's blur and highlights)
    public var glassEngine = "auto"
    /// the metal engine: how far the edges bend what is behind (points), its blur (points),
    /// its saturation (1: as it is)
    public var glassRefraction = 14.0
    public var glassBlur = 2.0
    public var glassSaturation = 1.5
    /// a selection lens moving to another item: its spring (seconds, 0: it jumps), its
    /// overshoot (0...1), how much it stretches on its way (0: none)
    public var glassLensResponse = 0.35
    public var glassLensBounce = 0.3
    public var glassLensStretch = 1.0
    /// skylandbar's animations: auto (none with macOS's Reduce Motion), full (always),
    /// reduced (never)
    public var motion = "auto"

    public init() {}

    public mutating func apply(_ key: String, _ value: String) -> String? {
        let (head, rest) = splitKey(key)
        switch head {
            case "color": return Value.setColor(&color, value, part: rest)
            case "border_color": return Value.setColor(&borderColor, value, part: rest)
            case "border_width": return Value.setNumber(&borderWidth, value, minimum: 0)
            case "glass_spacing": return Value.setNumber(&glassSpacing, value, minimum: 0)
            case "glass_engine": return Value.oneOf(&glassEngine, value, ["auto", "system", "metal", "backdrop"])
            case "glass_refraction": return Value.setNumber(&glassRefraction, value, minimum: 0)
            case "glass_blur": return Value.setNumber(&glassBlur, value, minimum: 0)
            case "glass_saturation": return Value.setNumber(&glassSaturation, value, minimum: 0)
            case "glass_lens_response": return Value.setNumber(&glassLensResponse, value, minimum: 0)
            case "glass_lens_bounce":
                var bounce = glassLensBounce
                if let error = Value.setNumber(&bounce, value, minimum: 0) { return error }
                glassLensBounce = min(1, bounce)
                return nil
            case "glass_lens_stretch": return Value.setNumber(&glassLensStretch, value, minimum: 0)
            case "motion": return Value.oneOf(&motion, value, ["auto", "full", "reduced"])
            case "position": return Value.oneOf(&position, value, ["top", "bottom"])
            case "height": return Value.setNumber(&height, value, minimum: 0)
            case "notch_display_height": return Value.setNumber(&notchDisplayHeight, value, minimum: 0)
            case "margin": return Value.setNumber(&margin, value)
            case "y_offset": return Value.setNumber(&yOffset, value)
            case "corner_radius": return Value.setNumber(&cornerRadius, value, minimum: 0)
            case "blur_radius": return Value.setNumber(&blurRadius, value, minimum: 0)
            case "padding_left": return Value.setNumber(&paddingLeft, value)
            case "padding_right": return Value.setNumber(&paddingRight, value)
            case "notch_width": return Value.setNumber(&notchWidth, value, minimum: 0)
            case "notch_offset": return Value.setNumber(&notchOffset, value)
            case "display":
                guard value == "main" || value == "all" || ItemProps.isNumberList(value) else {
                    return "'\(value)' is not main, all or display numbers"
                }
                display = value
                return nil
            case "hidden":
                if value == "current" {
                    hidden = value
                    return nil
                }
                var on = hidden != "off"
                if let error = Value.setBool(&on, value) { return error }
                hidden = on ? "on" : "off"
                return nil
            case "topmost":
                if value == "window" {
                    topmost = value
                    return nil
                }
                var on = topmost != "off"
                if let error = Value.setBool(&on, value) { return error }
                topmost = on ? "on" : "off"
                return nil
            case "sticky": return Value.setBool(&sticky, value)
            case "font_smoothing": return Value.setBool(&fontSmoothing, value)
            case "shadow": return Value.setBool(&shadow, value)
            case "glass": return Value.setGlass(&glass, value)
            default: return unknownProperty
        }
    }

    /// Whether there is a bar on display `number` (1-based, NSScreen order, 1 = main).
    public func isShown(onDisplay number: Int) -> Bool {
        switch display {
            case "all": return true
            case "main": return number == 1
            default: return display.split(separator: ",").compactMap { Int($0) }.contains(number)
        }
    }

    public var json: [String: Any] {
        [
            "position": position, "topmost": topmost, "sticky": sticky ? "on" : "off", "hidden": hidden,
            "shadow": shadow ? "on" : "off", "font_smoothing": fontSmoothing ? "on" : "off", "blur_radius": blurRadius,
            "margin": margin, "notch_display_height": notchDisplayHeight, "notch_width": notchWidth, "notch_offset": notchOffset,
            "display": display, "color": color.description, "border_color": borderColor.description, "border_width": borderWidth,
            "height": height, "y_offset": yOffset, "corner_radius": cornerRadius,
            "padding_left": paddingLeft, "padding_right": paddingRight, "glass": glass, "glass_spacing": glassSpacing,
            "glass_engine": glassEngine, "glass_refraction": glassRefraction, "glass_blur": glassBlur, "glass_saturation": glassSaturation,
            "glass_lens_response": glassLensResponse, "glass_lens_bounce": glassLensBounce, "glass_lens_stretch": glassLensStretch, "motion": motion,
        ]
    }
}
