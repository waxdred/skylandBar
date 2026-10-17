import AppKit
import SkylandBarCore

// The bar and popup windows and how items are drawn: background, icon, graph / slider /
// alias, label, each with sketchybar's paddings, offsets, fonts, colors, borders, shadows
// and images; Liquid Glass behind the backgrounds that ask for it.

enum Fonts {
    private static var cache: [FontSpec: NSFont] = [:]

    /// "Hack Nerd Font:Bold:14.0": CoreText's match for that family and style, as sketchybar
    /// does (a missing family gives CoreText's fallback, Helvetica, there too). "SF Pro" not
    /// installed as a font is the system font, the same face with SF Symbols' glyphs.
    static func font(_ spec: FontSpec) -> NSFont {
        if let font = cache[spec] { return font }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: spec.family, kCTFontStyleNameAttribute: spec.style, kCTFontSizeAttribute: spec.size,
        ] as CFDictionary)
        var result = CTFontCreateWithFontDescriptor(descriptor, 0, nil) as NSFont
        if spec.family.hasPrefix("SF Pro"), result.familyName != spec.family {
            result = NSFont.systemFont(ofSize: CGFloat(spec.size), weight: weight(spec.style))
        }
        cache[spec] = result
        return result
    }

    private static func weight(_ style: String) -> NSFont.Weight {
        switch style.lowercased() {
            case "ultralight": return .ultraLight
            case "thin": return .thin
            case "light": return .light
            case "medium": return .medium
            case "semibold": return .semibold
            case "bold": return .bold
            case "heavy": return .heavy
            case "black": return .black
            default: return .regular
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
        // the cache is by font spec, an animated size makes one font per frame: keep it small
        if cache.count > 256 { cache.removeAll() }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(text.font),
            .foregroundColor: color(text.highlight ? text.highlightColor : text.color),
        ]
        if text.shadow.drawing { attributes[.shadow] = shadow(text.shadow) }
        return attributes
    }

    /// The width a text takes, without its paddings.
    static func width(_ text: TextProps) -> Double { width(text.shown, font(text.font)) }

    /// sketchybar's: the glyphs' drawn width plus about a pixel, not the advance (Nerd Font
    /// icons draw wider than they advance); 1 for no string, as there
    static func width(_ string: String, _ font: NSFont) -> Double { metrics(string, font).width }

    /// How far the baseline goes below the middle: half the line's ascent minus its descent,
    /// rounded up (sketchybar's, on its y-up bar)
    static func baselineOffset(_ string: String, _ font: NSFont) -> Double { metrics(string, font).baseline }

    private struct MetricsKey: Hashable {
        let string: String
        let font: String
        let size: CGFloat
    }

    /// A text is measured at every layout and every draw, with the same strings again and
    /// again: CoreText once per string and font. Kept small: a clock makes a new one a minute.
    private static var measured: [MetricsKey: (width: Double, baseline: Double)] = [:]

    private static func metrics(_ string: String, _ font: NSFont) -> (width: Double, baseline: Double) {
        let key = MetricsKey(string: string, font: font.fontName, size: font.pointSize)
        if let known = measured[key] { return known }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let result = (width: Double(floor(CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).width + 1.5)), baseline: Double(ceil((ascent - descent) / 2)))
        if measured.count > 2048 { measured.removeAll() }
        measured[key] = result
        return result
    }
}

/// One item as laid out on one bar or popup.
struct PlacedItem: Equatable {
    let name: String
    let kind: String
    /// where its content starts (after `background.padding_left`)
    let x: Double
    let length: Double
    /// its row: the whole bar, or a popup row
    let top: Double
    let height: Double
    let props: ItemProps
    /// a graph's, a slider's or an alias's width, between the icon and the label
    let middle: Double
    let graphValues: [Double]
    let alias: NSImage?
    /// x of each part: icon, middle, label (with their paddings), and the texts' content
    /// widths; measured once, used by every draw, hit test and glass view
    let parts: (icon: Double, iconWidth: Double, middle: Double, label: Double, labelWidth: Double)

    init(name: String, kind: String, x: Double, length: Double, top: Double, height: Double, props: ItemProps,
         middle: Double = 0, graphValues: [Double] = [], alias: NSImage? = nil)
    {
        self.name = name
        self.kind = kind
        self.x = x
        self.length = length
        self.top = top
        self.height = height
        self.props = props
        self.middle = middle
        self.graphValues = graphValues
        self.alias = alias
        let measure: (TextProps) -> Double = Fonts.width, image: (ImageProps) -> Double = Images.width
        var cursor = x
        let icon = cursor, iconWidth = Layout.contentWidth(props.icon, measure: measure, image: image)
        if props.icon.drawing { cursor += props.icon.paddingLeft + iconWidth + props.icon.paddingRight }
        let middleX = cursor
        cursor += middle
        let labelWidth = Layout.contentWidth(props.label, measure: measure, image: image)
        parts = (icon, iconWidth, middleX, cursor, labelWidth)
    }

    var rect: NSRect { NSRect(x: x, y: top, width: length, height: height) }

    /// The same drawing: what it shows and where (its parts follow from these).
    static func == (a: PlacedItem, b: PlacedItem) -> Bool {
        a.name == b.name && a.kind == b.kind && a.x == b.x && a.length == b.length && a.top == b.top && a.height == b.height
            && a.middle == b.middle && a.alias === b.alias && a.graphValues == b.graphValues && a.props == b.props
    }
}

/// How a window's own background looks: the bar's, or a popup's.
struct PanelStyle: Equatable {
    var color = ARGB.clear
    var borderColor = ARGB.clear
    var borderWidth = 0.0
    var cornerRadius = 0.0
    var glass = "off"
    var fontSmoothing = false
    /// the notch's shape: flush with the top, rounded at the bottom (`cornerRadius`), with
    /// small outward curves (`flare`) where it meets the top edge
    var notch = false
    var flare = 0.0
    /// how close its glass backgrounds merge (the bar's glass_spacing)
    var glassSpacing = 0.0

    init() {}

    init(bar: BarProps) {
        color = bar.color
        borderColor = bar.borderColor
        borderWidth = bar.borderWidth
        cornerRadius = bar.cornerRadius
        glass = bar.glass
        fontSmoothing = bar.fontSmoothing
        glassSpacing = bar.glassSpacing
    }

    init(popup: PopupProps, fontSmoothing: Bool) {
        let background = popup.background
        if background.drawing {
            color = background.color
            borderColor = background.borderColor
            borderWidth = background.borderWidth
            glass = background.glass
        }
        cornerRadius = max(0, background.cornerRadius) // its own: concentric to nothing
        self.fontSmoothing = fontSmoothing
    }
}

final class BarView: NSView {
    var style = PanelStyle()
    var items: [PlacedItem] = []
    /// the size of the last drawing: a resized window draws again
    private(set) var drawnSize = NSSize.zero

    /// New items and style; a redraw (and new glass views) only when they change, so a
    /// script setting the same label, or an animation frame of another window, costs nothing.
    /// False when nothing changed.
    @discardableResult
    func show(_ items: [PlacedItem], style: PanelStyle) -> Bool {
        guard items != self.items || style != self.style || bounds.size != drawnSize else { return false }
        self.items = items
        self.style = style
        needsDisplay = true
        return true
    }

    /// Redraws just the texts that scroll.
    func redrawScrolling() {
        for item in items where item.props.scrollTexts && (item.props.icon.scrolls || item.props.label.scrolls) {
            setNeedsDisplay(item.rect.insetBy(dx: -4, dy: 0))
        }
    }

    var onItemEntered: ((String) -> Void)?
    var onItemExited: ((String) -> Void)?
    var onBarEntered: (() -> Void)?
    var onBarExited: (() -> Void)?
    var onClick: ((_ item: String, _ button: String, _ modifier: String) -> Void)?
    var onScroll: ((_ item: String?, _ delta: Double, _ modifier: String) -> Void)?
    /// a slider moved by the mouse: its percentage; `done` on mouse up
    var onSlide: ((_ item: String, _ percentage: Double, _ modifier: String, _ done: Bool) -> Void)?
    private var hovered: String?
    private var sliding: String?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Whether a text scrolls (`scroll_texts`), so the bar redraws it on a timer.
    var scrolls: Bool {
        items.contains { $0.props.scrollTexts && ($0.props.icon.scrolls || $0.props.label.scrolls) }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawnSize = bounds.size
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(style.fontSmoothing)
        let inset = style.borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = min(style.cornerRadius, rect.height / 2, rect.width / 2)
        let path = style.notch ? Self.notchPath(bounds, radius: style.cornerRadius, flare: style.flare)
            : NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if style.glass == "off" {
            Fonts.color(style.color).setFill()
            path.fill()
        }
        if style.borderWidth > 0 {
            Fonts.color(style.borderColor).setStroke()
            path.lineWidth = style.borderWidth
            path.stroke()
        }
        clipBackgrounds()
        for item in items { draw(item) }
    }

    /// The notch in a flipped `rect`: its top edge along the screen's, curving out by
    /// `flare` at each end, its bottom corners rounded by `radius`.
    static func notchPath(_ rect: NSRect, radius: Double, flare: Double) -> NSBezierPath {
        let w = Double(rect.width), h = Double(rect.height), r = min(flare, w / 4), big = max(0, min(radius, (w - 2 * r) / 2, h - r))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.curve(to: NSPoint(x: rect.minX + r, y: rect.minY + r), controlPoint1: NSPoint(x: rect.minX + r, y: rect.minY),
                   controlPoint2: NSPoint(x: rect.minX + r, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX + r, y: rect.minY + h - big))
        path.curve(to: NSPoint(x: rect.minX + r + big, y: rect.minY + h), controlPoint1: NSPoint(x: rect.minX + r, y: rect.minY + h),
                   controlPoint2: NSPoint(x: rect.minX + r, y: rect.minY + h))
        path.line(to: NSPoint(x: rect.minX + w - r - big, y: rect.minY + h))
        path.curve(to: NSPoint(x: rect.minX + w - r, y: rect.minY + h - big), controlPoint1: NSPoint(x: rect.minX + w - r, y: rect.minY + h),
                   controlPoint2: NSPoint(x: rect.minX + w - r, y: rect.minY + h))
        path.line(to: NSPoint(x: rect.minX + w - r, y: rect.minY + r))
        path.curve(to: NSPoint(x: rect.minX + w, y: rect.minY), controlPoint1: NSPoint(x: rect.minX + w - r, y: rect.minY),
                   controlPoint2: NSPoint(x: rect.minX + w - r, y: rect.minY))
        path.close()
        return path
    }

    private func center(_ item: PlacedItem) -> Double { item.top + item.height / 2 - item.props.yOffset } // y_offset up

    private func draw(_ item: PlacedItem) {
        let props = item.props
        let mid = center(item)
        if props.background.drawing { fill(props.background, x: item.x, width: item.length, mid: mid, row: item.height) }
        if item.kind == "bracket" { return }
        let parts = item.parts
        if props.icon.drawing { draw(props.icon, scroll: props.scrollTexts, x: parts.icon, width: parts.iconWidth, mid: mid, row: item.height) }
        switch item.kind {
            case "graph": drawGraph(item, x: parts.middle, mid: mid)
            case "slider": drawSlider(item, x: parts.middle, mid: mid)
            case "alias":
                if let image = item.alias {
                    let size = NSSize(width: image.size.width * props.alias.scale, height: image.size.height * props.alias.scale)
                    Images.draw(image, in: NSRect(x: parts.middle, y: mid - size.height / 2, width: size.width, height: size.height),
                                tint: props.alias.color)
                }
            default: break
        }
        if props.label.drawing { draw(props.label, scroll: props.scrollTexts, x: parts.label, width: parts.labelWidth, mid: mid, row: item.height) }
    }

    /// A text from `x` (its padding_left included), its content `width` wide.
    private func draw(_ text: TextProps, scroll: Bool, x: Double, width: Double, mid: Double, row: Double) {
        if text.background.drawing {
            fill(text.background, x: x, width: text.paddingLeft + width + text.paddingRight, mid: mid, row: row)
        }
        let start = x + text.paddingLeft
        let string = scroll && text.scrolls ? text.scrolled(Int(CACurrentMediaTime() / max(0.01, text.scrollDuration / 400))) : text.shown
        guard !string.isEmpty else { return }
        let font = Fonts.font(text.font)
        let measured = Fonts.width(string, font)
        var textX = start
        switch text.align {
            case "center": textX += (width - measured) / 2
            case "right": textX += width - measured
            default: break
        }
        NSGraphicsContext.saveGraphicsState()
        if text.width != nil || scroll { NSRect(x: start, y: 0, width: width, height: bounds.height).clip() }
        let baseline = mid + Fonts.baselineOffset(string, font) - text.yOffset
        // without .usesLineFragmentOrigin the rect's origin is the baseline
        NSAttributedString(string: string, attributes: Fonts.attributes(text))
            .draw(with: NSRect(x: textX, y: baseline, width: 1e5, height: 0), options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Where a background `width` wide from `x` goes, centered on `mid` (0 height: the row's).
    private func backgroundRect(_ background: BackgroundProps, x: Double, width: Double, mid: Double, row: Double) -> NSRect {
        let height = background.height > 0 ? background.height : row
        let inset = background.borderWidth / 2
        return NSRect(x: x + background.xOffset, y: mid - height / 2 - background.yOffset, width: width, height: height)
            .insetBy(dx: inset, dy: inset)
    }

    /// A background's corners: `concentric`, its window's radius less the gap between them
    /// (Apple's concentric shapes); 0 on glass, a capsule (Liquid Glass's default shape).
    func radius(_ background: BackgroundProps, _ rect: NSRect) -> Double {
        var radius = background.cornerRadius
        if radius < 0 {
            radius = max(0, style.cornerRadius - min(rect.minY - bounds.minY, rect.minX - bounds.minX, bounds.maxY - rect.maxY))
        } else if radius == 0 && background.glass != "off" {
            radius = rect.height / 2
        }
        return min(radius, rect.height / 2, rect.width / 2)
    }

    private func fill(_ background: BackgroundProps, x: Double, width: Double, mid: Double, row: Double) {
        let rect = backgroundRect(background, x: x, width: width, mid: mid, row: row)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = radius(background, rect)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if background.glass == "off" {
            NSGraphicsContext.saveGraphicsState()
            if background.shadow.drawing { Fonts.shadow(background.shadow).set() }
            Fonts.color(background.color).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = background.image
        if image.isShown, let picture = Images.image(image.string) {
            let size = Images.size(image)
            let frame = NSRect(x: rect.minX + image.paddingLeft, y: rect.midY - size.height / 2 - image.yOffset,
                               width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            if image.shadow.drawing { Fonts.shadow(image.shadow).set() }
            Images.draw(picture, in: frame, cornerRadius: image.cornerRadius, borderWidth: image.borderWidth, borderColor: image.borderColor)
            NSGraphicsContext.restoreGraphicsState()
        }
        if background.borderWidth > 0 {
            Fonts.color(background.borderColor).setStroke()
            path.lineWidth = background.borderWidth
            path.stroke()
        }
    }

    /// The backgrounds drawn as Liquid Glass, for the window to put glass views under them.
    func glassBackgrounds() -> [(rect: NSRect, background: BackgroundProps)] {
        drawnBackgrounds().filter { $0.background.glass != "off" }
    }

    /// Every background drawn, where it is.
    private func drawnBackgrounds() -> [(rect: NSRect, background: BackgroundProps)] {
        var result: [(rect: NSRect, background: BackgroundProps)] = []
        for item in items {
            let props = item.props, mid = center(item)
            func add(_ background: BackgroundProps, _ x: Double, _ width: Double) {
                guard background.drawing else { return }
                result.append((backgroundRect(background, x: x, width: width, mid: mid, row: item.height), background))
            }
            add(props.background, item.x, item.length)
            if item.kind == "bracket" { continue }
            let parts = item.parts
            if props.icon.drawing { add(props.icon.background, parts.icon, props.icon.paddingLeft + parts.iconWidth + props.icon.paddingRight) }
            if item.kind == "slider" { add(props.slider.background, parts.middle, props.slider.width) }
            if props.label.drawing { add(props.label.background, parts.label, props.label.paddingLeft + parts.labelWidth + props.label.paddingRight) }
        }
        return result
    }

    /// `background.clip` (0...1): how much of the bar under a background is cut out, so
    /// what is behind the bar shows through it. A glass background cuts it all: its glass
    /// view is under this view.
    private func clipBackgrounds() {
        let clipped = drawnBackgrounds().filter { $0.background.clip > 0 || $0.background.glass != "off" }
        guard !clipped.isEmpty, let context = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        context.compositingOperation = .destinationOut
        for (rect, background) in clipped {
            let radius = radius(background, rect)
            NSColor(white: 0, alpha: background.glass != "off" ? 1 : min(1, background.clip)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: graphs and sliders

    /// The values right-aligned, one point each, from the bottom of the background's height.
    private func drawGraph(_ item: PlacedItem, x: Double, mid: Double) {
        let graph = item.props.graph, values = item.graphValues
        guard graph.width > 0, !values.isEmpty else { return }
        let height = item.props.background.height > 0 ? item.props.background.height : item.height
        let bottom = mid + height / 2
        let first = x + graph.width - Double(values.count - 1)
        let points = values.enumerated().map { NSPoint(x: first + Double($0.offset), y: bottom - $0.element * height) }
        let line = NSBezierPath()
        line.move(to: points[0])
        for point in points.dropFirst() { line.line(to: point) }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: points[points.count - 1].x, y: bottom))
        area.line(to: NSPoint(x: points[0].x, y: bottom))
        area.close()
        Fonts.color(graph.fill).setFill()
        area.fill()
        Fonts.color(graph.color).setStroke()
        line.lineWidth = graph.lineWidth
        line.stroke()
    }

    private func drawSlider(_ item: PlacedItem, x: Double, mid: Double) {
        let slider = item.props.slider
        guard slider.width > 0 else { return }
        let track = slider.background
        if track.drawing { fill(track, x: x, width: slider.width, mid: mid, row: item.height) }
        let rect = backgroundRect(track, x: x, width: slider.width, mid: mid, row: item.height)
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width * slider.percentage / 100, height: rect.height)
        if filled.width > 0 {
            let radius = min(radius(track, rect), filled.height / 2, filled.width / 2)
            Fonts.color(slider.highlightColor).setFill()
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
        }
        let knob = slider.knob
        if knob.drawing, !knob.string.isEmpty {
            let font = Fonts.font(knob.font)
            let size = NSAttributedString(string: knob.string, attributes: [.font: font]).size()
            NSAttributedString(string: knob.string, attributes: Fonts.attributes(knob))
                .draw(at: NSPoint(x: rect.minX + rect.width * slider.percentage / 100 - size.width / 2,
                                  y: mid - (font.ascender - font.descender) / 2 - knob.yOffset))
        }
    }

    /// The slider under `point`, and the percentage there.
    private func slider(at point: NSPoint) -> (name: String, percentage: Double)? {
        guard let item = items.last(where: { $0.kind == "slider" && $0.rect.contains(point) }) else { return nil }
        let x = item.parts.middle, width = item.props.slider.width
        guard width > 0, Double(point.x) >= x - 4, Double(point.x) <= x + width + 4 else { return nil }
        return (item.name, (Double(point.x) - x) / width * 100)
    }

    // MARK: mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func point(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    private func item(at event: NSEvent) -> String? {
        let point = point(event)
        return items.last { $0.kind != "bracket" && $0.rect.contains(point) }?.name
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

    override func mouseDown(with event: NSEvent) {
        if let hit = slider(at: point(event)) {
            sliding = hit.name
            onSlide?(hit.name, hit.percentage, Self.modifier(event.modifierFlags), false)
            return
        }
        click(event, "left")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sliding, let item = items.first(where: { $0.name == sliding }), item.props.slider.width > 0 else { return }
        let percentage = (Double(point(event).x) - item.parts.middle) / item.props.slider.width * 100
        onSlide?(sliding, percentage, Self.modifier(event.modifierFlags), false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let sliding, let item = items.first(where: { $0.name == sliding }), item.props.slider.width > 0 else { return }
        self.sliding = nil
        let percentage = (Double(point(event).x) - item.parts.middle) / item.props.slider.width * 100
        onSlide?(sliding, percentage, Self.modifier(event.modifierFlags), true)
    }

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

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// The window's background blur: private, on our own window (no SIP needed).
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius")
@discardableResult
private func CGSSetWindowBackgroundBlurRadius(_ connection: Int32, _ window: UInt32, _ radius: Int32) -> Int32

/// The bar of one display, or a popup: a borderless panel that never takes the focus,
/// holding the item view over the glass views of its glass backgrounds.
final class BarWindow {
    let panel: NSPanel
    let view = BarView()
    /// 1-based, NSScreen order (1 = main)
    let display: Int
    private let root = FlippedView()
    private var panelGlass: NSView?
    private var itemGlass: [NSView] = []
    /// the item glass views' parent: an NSGlassEffectContainerView's content (macOS 26),
    /// which renders them in one pass and merges those closer than its spacing
    private var glassHolder: NSView?

    init(display: Int) {
        self.display = display
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 25), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        root.frame = NSRect(x: 0, y: 0, width: 100, height: 25)
        view.frame = root.bounds
        view.autoresizingMask = [.width, .height]
        root.addSubview(view)
        panel.contentView = root
    }

    func configure(_ bar: BarProps, screen: NSScreen) {
        let frame = screen.frame
        var height = bar.height
        if bar.notchDisplayHeight > 0, screen.safeAreaInsets.top > 0 { height = bar.notchDisplayHeight }
        let y = bar.position == "bottom" ? frame.minY + bar.yOffset : frame.maxY - height - bar.yOffset
        panel.setFrame(NSRect(x: frame.minX + bar.margin, y: y, width: max(1, frame.width - 2 * bar.margin), height: max(1, height)),
                       display: false)
        panel.level = Self.level(bar.topmost)
        panel.collectionBehavior = Self.behavior(sticky: bar.sticky)
        panel.hasShadow = bar.shadow
        setBlur(bar.glass == "off" ? bar.blurRadius : 0)
    }

    func configurePopup(_ popup: PopupProps, frame: NSRect, bar: BarProps) {
        panel.setFrame(frame, display: false)
        panel.level = popup.topmost ? .popUpMenu : NSWindow.Level(rawValue: Self.level(bar.topmost).rawValue + 1)
        panel.collectionBehavior = Self.behavior(sticky: bar.sticky)
        panel.hasShadow = false
        setBlur(popup.background.drawing && popup.background.glass != "off" ? 0 : popup.blurRadius)
    }

    /// The notch's window: over the menu bar, at `frame`, on every Space and over full
    /// screen apps; a shadow once it opens.
    func configureNotch(frame: NSRect, open: Bool) {
        panel.setFrame(frame, display: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = open
        setBlur(0)
    }

    private static func level(_ topmost: String) -> NSWindow.Level {
        switch topmost {
            case "on": return .statusBar
            case "window": return .floating
            default: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
        }
    }

    private static func behavior(sticky: Bool) -> NSWindow.CollectionBehavior {
        sticky ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary] : [.ignoresCycle, .fullScreenAuxiliary]
    }

    private var blur = -1.0

    private func setBlur(_ radius: Double) {
        guard radius != blur else { return }
        blur = radius
        CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), UInt32(panel.windowNumber), Int32(radius))
    }

    /// Glass views under the view: one for the window when its style asks for it, one per
    /// glass background; call it after setting the view's items.
    func updateGlass() {
        let style = view.style
        if style.glass != "off" {
            let glass = panelGlass ?? Glass.makeView()
            if panelGlass == nil {
                glass.frame = root.bounds
                glass.autoresizingMask = [.width, .height]
                root.addSubview(glass, positioned: .below, relativeTo: nil)
                panelGlass = glass
            }
            Glass.update(glass, style: style.glass, tint: style.color, cornerRadius: style.cornerRadius)
        } else if let glass = panelGlass {
            glass.removeFromSuperview()
            panelGlass = nil
        }
        let backgrounds = view.glassBackgrounds()
        if glassHolder == nil && !backgrounds.isEmpty {
            let (container, holder) = Glass.makeContainer()
            container.frame = root.bounds
            container.autoresizingMask = [.width, .height]
            root.addSubview(container, positioned: .below, relativeTo: view)
            glassHolder = holder
        }
        if let glassHolder { Glass.setSpacing(glassHolder, style.glassSpacing) }
        while itemGlass.count > backgrounds.count { itemGlass.removeLast().removeFromSuperview() }
        while itemGlass.count < backgrounds.count {
            let glass = Glass.makeView()
            glassHolder?.addSubview(glass)
            itemGlass.append(glass)
        }
        for (glass, background) in zip(itemGlass, backgrounds) {
            glass.frame = background.rect
            Glass.update(glass, style: background.background.glass, tint: background.background.color,
                         cornerRadius: view.radius(background.background, background.rect))
        }
    }
}

/// Calls `tick` at each refresh of the view's display (its display link: 60 or 120 Hz,
/// nothing while the display sleeps), or 60 times a second without a view.
final class FrameTicker: NSObject {
    private let tick: () -> Void
    private var link: CADisplayLink?
    private var timer: Timer?

    init(view: NSView?, tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        if let view {
            let link = view.displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func step() { tick() }

    /// The link holds its target: stop it to let both go.
    func stop() {
        link?.invalidate()
        timer?.invalidate()
    }
}
