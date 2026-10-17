import AppKit
import SkylandBarCore

// The bar windows and how items are drawn: background, icon, label, each with sketchybar's
// paddings, offsets, fonts, colors, borders and shadows.

enum Fonts {
    private static var cache: [FontSpec: NSFont] = [:]

    /// "Hack Nerd Font:Bold:14.0": the family's face named Bold, else a font of that
    /// PostScript name, else the family at the style's weight, else the system font.
    static func font(_ spec: FontSpec) -> NSFont {
        if let font = cache[spec] { return font }
        let size = CGFloat(spec.size)
        var font: NSFont? = nil
        let descriptor = NSFontDescriptor(fontAttributes: [.family: spec.family, .face: spec.style])
        if let exact = NSFont(descriptor: descriptor, size: size), exact.familyName == spec.family {
            font = exact
        } else if let named = NSFont(name: spec.family, size: size) ?? NSFont(name: "\(spec.family)-\(spec.style)", size: size) {
            font = named
        } else {
            font = NSFontManager.shared.font(withFamily: spec.family, traits: [], weight: managerWeight(spec.style), size: size)
        }
        let result = font ?? NSFont.systemFont(ofSize: size, weight: weight(spec.style))
        cache[spec] = result
        return result
    }

    private static func weight(_ style: String) -> NSFont.Weight {
        switch style.lowercased() {
            case "ultralight", "thin": return .thin
            case "light": return .light
            case "medium": return .medium
            case "semibold": return .semibold
            case "bold": return .bold
            case "heavy", "extrabold": return .heavy
            case "black": return .black
            default: return .regular
        }
    }

    /// NSFontManager's 0...15 scale, 5 regular, 9 bold
    private static func managerWeight(_ style: String) -> Int {
        switch style.lowercased() {
            case "light": return 3
            case "medium": return 6
            case "semibold": return 8
            case "bold": return 9
            case "heavy", "black": return 11
            default: return 5
        }
    }

    static func color(_ color: ARGB) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    static func shadow(_ props: ShadowProps) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color(props.color)
        let angle = props.angle * .pi / 180
        // the view is flipped, NSShadow offsets are not: positive height goes up
        shadow.shadowOffset = NSSize(width: cos(angle) * props.distance, height: -sin(angle) * props.distance)
        return shadow
    }

    static func attributes(_ text: TextProps) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(text.font),
            .foregroundColor: color(text.highlight ? text.highlightColor : text.color),
        ]
        if text.shadow.drawing { attributes[.shadow] = shadow(text.shadow) }
        return attributes
    }

    /// The width a text takes, without its paddings.
    static func width(_ text: TextProps) -> Double {
        if text.shown.isEmpty { return 0 }
        return ceil(NSAttributedString(string: text.shown, attributes: [.font: font(text.font)]).size().width)
    }
}

/// One item as laid out on one bar.
struct PlacedItem {
    var name: String
    var x: Double
    var length: Double
    var props: ItemProps
}

final class BarView: NSView {
    var bar = BarProps()
    var items: [PlacedItem] = []

    var onItemEntered: ((String) -> Void)?
    var onItemExited: ((String) -> Void)?
    var onBarEntered: (() -> Void)?
    var onBarExited: (() -> Void)?
    var onClick: ((_ item: String, _ button: String, _ modifier: String) -> Void)?
    var onScroll: ((_ item: String?, _ delta: Double, _ modifier: String) -> Void)?
    private var hovered: String?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(bar.fontSmoothing)
        let inset = bar.borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = min(bar.cornerRadius, rect.height / 2, rect.width / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        Fonts.color(bar.color).setFill()
        path.fill()
        if bar.borderWidth > 0 {
            Fonts.color(bar.borderColor).setStroke()
            path.lineWidth = bar.borderWidth
            path.stroke()
        }
        for item in items { draw(item) }
    }

    private func draw(_ item: PlacedItem) {
        let props = item.props
        let mid = bounds.height / 2 - props.yOffset // y_offset up
        if props.background.drawing { fill(props.background, x: item.x, width: item.length, mid: mid) }
        var cursor = item.x
        for text in [props.icon, props.label] where text.drawing {
            let measured = Fonts.width(text)
            let width = text.width ?? measured
            if text.background.drawing {
                fill(text.background, x: cursor, width: text.paddingLeft + width + text.paddingRight, mid: mid)
            }
            cursor += text.paddingLeft
            if !text.shown.isEmpty {
                let font = Fonts.font(text.font)
                let height = font.ascender - font.descender
                var x = cursor
                if text.width != nil {
                    switch text.align {
                        case "center": x += (width - measured) / 2
                        case "right": x += width - measured
                        default: break
                    }
                }
                NSGraphicsContext.saveGraphicsState()
                if text.width != nil { NSRect(x: cursor, y: 0, width: width, height: bounds.height).clip() }
                NSAttributedString(string: text.shown, attributes: Fonts.attributes(text))
                    .draw(at: NSPoint(x: x, y: mid - height / 2 - text.yOffset))
                NSGraphicsContext.restoreGraphicsState()
            }
            cursor += width + text.paddingRight
        }
    }

    /// A background `width` wide from `x`, centered on `mid` (0 height: the bar's).
    private func fill(_ background: BackgroundProps, x: Double, width: Double, mid: Double) {
        let height = background.height > 0 ? background.height : bounds.height
        let inset = background.borderWidth / 2
        let rect = NSRect(x: x + background.xOffset, y: mid - height / 2 - background.yOffset, width: width, height: height)
            .insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(background.cornerRadius, rect.height / 2, rect.width / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        if background.shadow.drawing { Fonts.shadow(background.shadow).set() }
        Fonts.color(background.color).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        if background.borderWidth > 0 {
            Fonts.color(background.borderColor).setStroke()
            path.lineWidth = background.borderWidth
            path.stroke()
        }
    }

    // MARK: mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func item(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil)
        return items.last { Double(point.x) >= $0.x && Double(point.x) < $0.x + $0.length }?.name
    }

    private func hover(_ name: String?) {
        guard name != hovered else { return }
        if let hovered { onItemExited?(hovered) }
        hovered = name
        if let name { onItemEntered?(name) }
    }

    override func mouseEntered(with event: NSEvent) {
        onBarEntered?()
        hover(item(at: event))
    }

    override func mouseExited(with event: NSEvent) {
        hover(nil)
        onBarExited?()
    }

    override func mouseMoved(with event: NSEvent) { hover(item(at: event)) }

    override func mouseDown(with event: NSEvent) { click(event, "left") }
    override func rightMouseDown(with event: NSEvent) { click(event, "right") }
    override func otherMouseDown(with event: NSEvent) { click(event, "other") }

    private func click(_ event: NSEvent, _ button: String) {
        guard let name = item(at: event) else { return }
        onClick?(name, button, Self.modifier(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        onScroll?(item(at: event), Double(event.scrollingDeltaY), Self.modifier(event.modifierFlags))
    }

    /// sketchybar's MODIFIER: shift, ctrl, alt, cmd or none
    static func modifier(_ flags: NSEvent.ModifierFlags) -> String {
        if flags.contains(.shift) { return "shift" }
        if flags.contains(.control) { return "ctrl" }
        if flags.contains(.option) { return "alt" }
        if flags.contains(.command) { return "cmd" }
        return "none"
    }
}

// The bar window's background blur: private, on our own window (no SIP needed).
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
@discardableResult
private func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ window: UInt32, _ radius: Int32) -> Int32

/// The bar of one display: a borderless, click-through-free panel on every Space.
final class BarWindow {
    let panel: NSPanel
    let view = BarView()
    /// 1-based, NSScreen order (1 = main)
    let display: Int

    init(display: Int) {
        self.display = display
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 25), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = view
    }

    func configure(_ bar: BarProps, screen: NSScreen) {
        let frame = screen.frame
        var height = bar.height
        if bar.notchDisplayHeight > 0, screen.safeAreaInsets.top > 0 { height = bar.notchDisplayHeight }
        let y = bar.position == "bottom" ? frame.minY + bar.yOffset : frame.maxY - height - bar.yOffset
        panel.setFrame(NSRect(x: frame.minX + bar.margin, y: y, width: max(1, frame.width - 2 * bar.margin), height: max(1, height)),
                       display: false)
        switch bar.topmost {
            case "on": panel.level = .statusBar
            case "window": panel.level = .floating
            default: panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
        }
        panel.collectionBehavior = bar.sticky
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = bar.shadow
        view.bar = bar
        CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), UInt32(panel.windowNumber), Int32(bar.blurRadius))
    }
}
