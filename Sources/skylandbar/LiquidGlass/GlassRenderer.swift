import AppKit
import SkylandBarCore

// skylandbar's Liquid Glass: the glass under a window's items, drawn by one of four engines.
//   native    Apple's Liquid Glass through SwiftUI (glassEffect, GlassEffectContainer), its
//             lenses animated by SwiftUI (macOS 26, built with its SDK; NativeGlass.swift)
//   system    NSGlassEffectView in an NSGlassEffectContainerView (macOS 26)
//   metal     what is behind the window (ScreenCaptureKit) through a shader: refraction at
//             the edges, chromatic aberration, a light blur, saturation, rim light, sheen,
//             and shapes that melt together when closer than glass_spacing (any macOS)
//   backdrop  Core Animation's backdrop layer (blur, saturation) under highlight layers:
//             no refraction, no permission
// `glass_engine=auto` takes the first one this Mac can do.

/// One glass shape, in the window's flipped coordinates (points).
struct GlassShape: Equatable {
    var rect: NSRect
    var radius: Double
    var tint: ARGB
    /// regular | clear | lens (inside another shape: a selection, Apple's tab bar style)
    var style: String
    /// a moving lens, lifted (0...1): it magnifies more, its rim and shade grow
    var lift = 0.0
    /// a lens: the drop it leaves behind while it moves, melted into it
    var tail: NSRect?
}

struct GlassSettings: Equatable {
    var engine = "auto"
    /// the metal engine: snapshot | live (BarProps.glassCapture)
    var capture = "snapshot"
    var spacing = 0.0
    var refraction = 14.0
    var blur = 2.0
    var saturation = 1.5
    var lensResponse = 0.35
    var lensBounce = 0.3
    var lensStretch = 1.0
    /// the Reduce Motion setting: lenses do not slide
    var reduceMotion = false
    /// a lens follows the fingers (a workspace swipe): engines that animate lenses keep close
    var following = false
    /// screen (AppKit) area to see behind even with no glass yet: a glass notch, closed, keeps
    /// what is behind its open size ready, so it has glass from its first frame
    var captureArea: NSRect?

    init() {}

    init(bar: BarProps) {
        engine = bar.glassEngine
        capture = bar.glassCapture
        spacing = bar.glassSpacing
        refraction = bar.glassRefraction
        blur = bar.glassBlur
        saturation = bar.glassSaturation
        lensResponse = bar.glassLensResponse
        lensBounce = bar.glassLensBounce
        lensStretch = bar.glassLensStretch
    }
}

/// The glass of a window: its view fills the window, under the items' view.
protocol GlassRenderer: AnyObject {
    var view: NSView { get }
    /// it cannot go on (metal: the capture stopped): the window takes another engine
    var failed: Bool { get }
    func update(_ shapes: [GlassShape], settings: GlassSettings, window: NSWindow)
    /// true: given the lenses' targets, it animates them itself (native); false: the bar
    /// gives it each frame of LensMotion
    var animatesLenses: Bool { get }
}

extension GlassRenderer {
    var animatesLenses: Bool { false }
}

enum GlassEngine {
    static var systemAvailable: Bool { Glass.effectView != nil }

    private static var said = Set<String>()
    private static var asked = false

    /// The engine a setting gives on this Mac, said once on stderr.
    static func resolve(_ setting: String) -> String {
        var engine: String
        switch setting {
            case "native": engine = NativeGlassSupport.available ? "native" : resolve("auto")
            case "system": engine = systemAvailable ? "system" : resolve("auto")
            case "backdrop": engine = "backdrop"
            case "metal":
                engine = MetalGlass.isAvailable ? "metal" : "backdrop"
                if engine != "metal" && !asked { // ask once; macOS wants the bar restarted after
                    asked = true
                    CGRequestScreenCaptureAccess()
                }
            default: engine = systemAvailable ? "system" : MetalGlass.isAvailable ? "metal" : "backdrop"
        }
        if said.insert("\(setting)>\(engine)").inserted {
            let why = engine == "backdrop" && !systemAvailable
                ? " (metal, with refraction, needs Screen Recording: allow skylandbar in System Settings, then restart it)" : ""
            FileHandle.standardError.write(Data("skylandbar: glass: \(engine)\(why)\n".utf8))
        }
        return engine
    }

    static func make(_ engine: String) -> GlassRenderer {
        switch engine {
            case "native": return NativeGlassSupport.make() ?? SystemGlass()
            case "system": return SystemGlass()
            case "metal": return MetalGlass() ?? BackdropGlass()
            default: return BackdropGlass()
        }
    }
}

// MARK: system

/// Apple's glass: an NSGlassEffectView per shape, in NSGlassEffectContainerViews: one for the
/// groups (closer than glass_spacing they melt), one over it for lenses and hover drops, glass
/// of their own; a lens's drop left behind melts into it there, as a liquid would. skylandbar's
/// look on it all (GlassLook).
final class SystemGlass: GlassRenderer {
    let view: NSView = FlippedView()
    private let bodies: (container: NSView, holder: NSView)
    private let drops: (container: NSView, holder: NSView)
    private var bodyViews: [NSView] = []
    private var dropViews: [NSView] = []
    private var rims: [GlassRim] = []
    let failed = false

    init() {
        bodies = Glass.makeContainer()
        drops = Glass.makeContainer()
        for part in [bodies.container, drops.container] {
            part.frame = view.bounds
            part.autoresizingMask = [.width, .height]
            view.addSubview(part)
        }
        view.wantsLayer = true
    }

    func update(_ shapes: [GlassShape], settings: GlassSettings, window: NSWindow) {
        let isDrop = { (style: String) in style == "lens" || style == "hover" }
        var groupShapes: [GlassShape] = [], dropShapes: [GlassShape] = []
        for shape in shapes {
            guard isDrop(shape.style) else { groupShapes.append(shape); continue }
            dropShapes.append(shape)
            if let tail = shape.tail, tail.width > 0 { // its drop left behind, the same glass
                var drop = shape
                drop.rect = tail
                drop.radius = min(shape.radius, Double(min(tail.width, tail.height)) / 2)
                drop.tail = nil
                dropShapes.append(drop)
            }
        }
        Glass.setSpacing(bodies.holder, settings.spacing)
        Glass.setSpacing(drops.holder, 14) // a lens and its drop melt while near
        place(groupShapes, in: bodies.holder, views: &bodyViews)
        // Apple's tint is dense: a drop at half its tint keeps what is behind showing through it
        place(dropShapes.map { var d = $0; d.tint = ARGB(UInt32(d.tint.alpha * 0.5 * 255) << 24 | d.tint.value & 0xFFFFFF); return d },
              in: drops.holder, views: &dropViews)
        GlassLook.apply(bodies.container, settings: settings,
                        height: groupShapes.map { Double(min($0.rect.width, $0.rect.height)) }.min() ?? 36)
        // the double rims, over all the glass
        let rimmed = groupShapes.map { ($0, 1.0) } + dropShapes.map { ($0, 1.5 + 0.5 * $0.lift) }
        while rims.count > rimmed.count { rims.removeLast().removeFromSuperlayer() }
        while rims.count < rimmed.count {
            let rim = GlassRim()
            rim.zPosition = 10 // over the glass views' own layers
            view.layer?.addSublayer(rim)
            rims.append(rim)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (rim, (shape, strength)) in zip(rims, rimmed) { rim.set(shape.rect, radius: shape.radius, strength: strength) }
        CATransaction.commit()
        if let lens = dropShapes.first {
            GlassLook.apply(drops.container, settings: settings, height: Double(min(lens.rect.width, lens.rect.height)),
                            lift: dropShapes.map(\.lift).max() ?? 0)
        }
    }

    private func place(_ shapes: [GlassShape], in holder: NSView, views: inout [NSView]) {
        while views.count > shapes.count { views.removeLast().removeFromSuperview() }
        while views.count < shapes.count {
            let glass = Glass.makeView()
            holder.addSubview(glass)
            views.append(glass)
        }
        for (glass, shape) in zip(views, shapes) {
            glass.frame = shape.rect
            Glass.update(glass, style: shape.style, tint: shape.tint, cornerRadius: shape.radius)
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: backdrop

/// Core Animation's backdrop layer (what vibrancy uses: the window server's blur of what is
/// behind the window) with a saturation boost, under a tint, a sheen, a rim light and a
/// soft shadow, per shape.
final class BackdropGlass: GlassRenderer {
    let view: NSView = LayerHost()
    private var layers: [BackdropShapeLayer] = []
    let failed = false

    func update(_ shapes: [GlassShape], settings: GlassSettings, window: NSWindow) {
        guard let host = view.layer else { return }
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        while layers.count > shapes.count { layers.removeLast().removeFromSuperlayer() }
        while layers.count < shapes.count {
            let layer = BackdropShapeLayer()
            host.addSublayer(layer)
            layers.append(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, shape) in zip(layers, shapes) {
            // the host is not flipped: y from the bottom
            let rect = NSRect(x: shape.rect.minX, y: view.bounds.height - shape.rect.maxY, width: shape.rect.width, height: shape.rect.height)
            layer.configure(rect: rect, shape: shape, settings: settings, dark: dark)
        }
        CATransaction.commit()
    }
}

/// A layer-backed view whose sublayers are the glass.
private final class LayerHost: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // the items' view takes the mouse
}

private final class BackdropShapeLayer: CALayer {
    private let clip = CALayer()
    private let backdrop = BackdropShapeLayer.makeBackdrop()
    private let tint = CALayer()
    private let sheen = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimShape = CAShapeLayer()
    private var applied: (blur: Double, saturation: Double)?

    override init() {
        super.init()
        clip.masksToBounds = true
        clip.cornerCurve = .continuous
        clip.addSublayer(backdrop)
        clip.addSublayer(tint)
        clip.addSublayer(sheen)
        addSublayer(clip)
        rimShape.fillColor = nil
        rimShape.strokeColor = NSColor.black.cgColor
        rimShape.lineWidth = 1
        rim.mask = rimShape
        addSublayer(rim)
        shadowColor = NSColor.black.cgColor
        shadowOffset = CGSize(width: 0, height: -2)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }

    func configure(rect: NSRect, shape: GlassShape, settings: GlassSettings, dark: Bool) {
        frame = rect
        let bounds = CGRect(origin: .zero, size: rect.size)
        let radius = CGFloat(shape.radius)
        clip.frame = bounds
        clip.cornerRadius = radius
        backdrop.frame = bounds
        tint.frame = bounds
        sheen.frame = bounds
        rim.frame = bounds
        rimShape.frame = bounds
        let outline = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: max(0, radius - 0.5), cornerHeight: max(0, radius - 0.5),
                             transform: nil)
        rimShape.path = outline
        shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let clear = shape.style == "clear"
        let lift = CGFloat(shape.lift) // a moving lens: lifted, its shadow wider
        shadowOpacity = Float(clear ? 0.08 : 0.18 + 0.12 * shape.lift)
        shadowRadius = 8 + 6 * lift
        // the glass's own light: darker and denser in dark mode, milky in light mode, then its tint
        let base = dark ? NSColor(white: 0.08, alpha: clear ? 0.10 : 0.22) : NSColor(white: 1, alpha: clear ? 0.12 : 0.30)
        tint.backgroundColor = (shape.tint.alpha > 0 ? Fonts.color(shape.tint) : base).cgColor
        sheen.colors = [NSColor(white: 1, alpha: dark ? 0.10 : 0.22).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 1) // the top (the layer is not flipped)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.45)
        // the rim: bright where light from the top left falls, softer opposite
        rim.colors = [NSColor(white: 1, alpha: dark ? 0.55 : 0.85).cgColor, NSColor(white: 1, alpha: 0.06).cgColor,
                      NSColor(white: 1, alpha: dark ? 0.22 : 0.35).cgColor]
        rim.locations = [0, 0.55, 1]
        rim.startPoint = CGPoint(x: 0, y: 1)
        rim.endPoint = CGPoint(x: 1, y: 0)
        let wanted = (blur: max(1, settings.blur * 4), saturation: settings.saturation)
        if applied.map({ $0.blur != wanted.blur || $0.saturation != wanted.saturation }) ?? true {
            applied = wanted
            backdrop.filters = [Self.filter("gaussianBlur", ["inputRadius": wanted.blur]),
                                Self.filter("colorSaturate", ["inputAmount": wanted.saturation])].compactMap { $0 }
        }
    }

    /// CABackdropLayer (private, in QuartzCore): the window server's picture of what is behind
    /// the window; a plain layer if this macOS has none.
    private static func makeBackdrop() -> CALayer {
        guard let type = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return CALayer() }
        let layer = type.init()
        set(layer, "windowServerAware", true)
        set(layer, "scale", 0.25) // drawn at a quarter: it is blurred anyway
        return layer
    }

    /// A private CAFilter ("gaussianBlur", "colorSaturate") with its inputs; nil without one.
    private static func filter(_ type: String, _ inputs: [String: Any]) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") else { return nil }
        let make = NSSelectorFromString("filterWithType:")
        let object = filterClass as AnyObject
        guard object.responds(to: make), let filter = object.perform(make, with: type)?.takeUnretainedValue() as? NSObject else { return nil }
        for (key, value) in inputs { filter.setValue(value, forKey: key) }
        filter.setValue(type, forKey: "name")
        return filter
    }

    /// A private property, only where the layer has it (a missing key would raise).
    private static func set(_ object: NSObject, _ key: String, _ value: Any) {
        let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
        if object.responds(to: setter) { object.setValue(value, forKey: key) }
    }
}
