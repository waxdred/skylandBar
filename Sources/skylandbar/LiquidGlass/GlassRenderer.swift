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
//   flat      no glass: opaque panels in their tint, a thin line, a faint dot grid (the
//             glyph theme, Nothing OS like); never taken by auto
// `glass_engine=auto` takes the first one this Mac can do.

/// One glass shape, in the window's flipped coordinates (points).
struct GlassShape: Equatable {
    /// for a rim: where and how round
    var part: (rect: NSRect, radius: Double) { (rect, radius) }
    var rect: NSRect
    var radius: Double
    var tint: ARGB
    /// regular | clear | lens (inside another shape: a selection, Apple's tab bar style)
    var style: String
    /// a moving lens, lifted (0...1): it magnifies more, its rim and shade grow
    var lift = 0.0
    /// a lens: the drop it leaves behind while it moves, melted into it
    var tail: NSRect?
    /// inner corners where it meets its group (BackgroundProps.fillet), 0: the rim's default
    var fillet = 0.0
    /// a moving lens: the side it goes to (-1 left, 1 right, 0 at rest) and how stretched it
    /// is (0...1): Apple's glass draws it as a drop, a round head and a thinning body
    var heading = 0.0
    var stretch = 0.0
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
            case "flat": engine = "flat"
            case "metal":
                engine = MetalGlass.isAvailable ? "metal" : "backdrop"
                if engine != "metal" && !asked { // ask once; macOS wants the bar restarted after
                    asked = true
                    CGRequestScreenCaptureAccess()
                }
                // Apple's glass where macOS has it (26+), else the backdrop blur: the metal engine's
                // screen capture turned protected videos black and froze behind scrolling; on demand only
                default: engine = systemAvailable ? "system" : "backdrop"
        }
        if said.insert("\(setting)>\(engine)").inserted {
            let why = engine == "backdrop" && !systemAvailable && setting == "metal"
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
            case "flat": return FlatGlass()
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
        let isDrop = { (style: String) in style == "lens" || style == "hover" || style == "bead" }
        var groupShapes: [GlassShape] = [], dropShapes: [GlassShape] = []
        for shape in shapes {
            guard isDrop(shape.style) else { groupShapes.append(shape); continue }
            if shape.style == "lens", shape.heading != 0 {
                dropShapes += Self.drop(shape)
                continue
            }
            dropShapes.append(shape)
            if let tail = shape.tail, tail.width > 0 { // its drop left behind, the same glass
                var drop = shape
                // round as it shrinks: a drop (the shader's narrowed into a tall pill on its own);
                // gone once small, not a ring left by the item
                let side = min(tail.width, tail.height)
                guard side > shape.rect.height * 0.2 else { continue } // small enough to go without a pop
                drop.rect = NSRect(x: tail.midX - side / 2, y: tail.midY - side / 2, width: side, height: side)
                drop.radius = Double(side) / 2
                drop.tail = nil
                drop.style = "tail" // no rim: Apple's glass melts it into the lens, a rim would not
                dropShapes.append(drop)
                if let neck = neck(from: tail, to: shape) { dropShapes.append(neck) }
            }
        }
        Glass.setSpacing(bodies.holder, settings.spacing)
        Glass.setSpacing(drops.holder, 12) // the neck melts into the drop and the lens: thick where it joins them
        place(groupShapes, in: bodies.holder, views: &bodyViews)
        // Apple's tint is dense: a drop at half its tint keeps what is behind showing through it
        // half the tint (Apple's is dense), its strength in steps: the item's color fades in over
        // its animation, and every new tint rebuilds the glass
        place(dropShapes.map { var d = $0; d.tint = ARGB(UInt32((d.tint.alpha * 4).rounded() / 4 * 0.5 * 255) << 24 | d.tint.value & 0xFFFFFF); return d },
              in: drops.holder, views: &dropViews, keep: true)
        GlassLook.apply(bodies.container, settings: settings,
                        height: groupShapes.map { Double(min($0.rect.width, $0.rect.height)) }.min() ?? 36)
        // the double rims, over all the glass; a lens and its drop's beads get one rim around
        // them all, in colors along the diagonal (more while it moves: its shape shows)
        let lensParts = dropShapes.filter { $0.style == "lens" || $0.style == "bead" }
        let lensLift = lensParts.map(\.lift).max() ?? 0
        // groups: their tint filled under the rim. Apple's glass took none of it (any tint, opaque
        // black or red, came out the same light gray): background.color, glass_tint and the menu
        // bar's menubar_opacity did nothing. The most opaque tint of shapes that melt together.
        typealias Rimmed = (shapes: [(rect: NSRect, radius: Double)], strength: Double, colors: Double, tint: ARGB?, fillet: Double)
        var rimmed: [Rimmed] = []
        for group in Self.overlapping(groupShapes) {
            rimmed.append((group.map(\.part), 1.0, 0.0, group.map(\.tint).max { $0.alpha < $1.alpha }, group.map(\.fillet).max() ?? 0))
        }
        for group in Self.overlapping(lensParts) {
            rimmed.append((group.map(\.part), 1.5 + 0.5 * lensLift, 0.35 + 0.65 * lensLift, nil, 0))
        }
        for hover in dropShapes where hover.style == "hover" {
            rimmed.append(([hover.part], 1.5 + 0.5 * hover.lift, 0.0, nil, 0))
        }
        while rims.count > rimmed.count { rims.removeLast().removeFromSuperlayer() }
        while rims.count < rimmed.count {
            let rim = GlassRim()
            rim.zPosition = 10 // over the glass views' own layers
            view.layer?.addSublayer(rim)
            rims.append(rim)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (rim, (shapes, strength, colors, tint, fillet)) in zip(rims, rimmed) {
            rim.set(shapes, strength: strength, colors: colors, fill: tint, fillet: fillet)
        }
        maskCuts()
        CATransaction.commit()
        if let lens = dropShapes.first {
            GlassLook.apply(drops.container, settings: settings, height: Double(min(lens.rect.width, lens.rect.height)),
                            lift: dropShapes.map(\.lift).max() ?? 0)
        }
    }

    /// A moving lens as a drop of water: a round head at its leading end, then beads smaller
    /// and smaller back to its trailing end, which the container melts into one shape that
    /// thins behind the head. Not stretched, the beads are as big as the head: the lens as it
    /// is. As the trailing end catches up, they go back into the head: round again.
    private static func drop(_ lens: GlassShape) -> [GlassShape] {
        let r = lens.rect, side = r.height
        guard r.width > side + 1 else { return [lens] }
        let right = lens.heading > 0
        var head = lens
        head.rect = NSRect(x: right ? r.maxX - side : r.minX, y: r.minY, width: side, height: side)
        head.radius = side / 2
        var parts = [head]
        let count = min(6, max(1, Int(((r.width - side) / (side * 0.3)).rounded(.up))))
        for i in 1 ... count {
            let f = Double(i) / Double(count)
            let size = side * (1 - 0.55 * min(1, max(0, lens.stretch)) * f)
            let from = head.rect.midX, to = right ? r.minX + size / 2 : r.maxX - size / 2
            let x = from + (to - from) * f
            var bead = lens
            bead.rect = NSRect(x: x - size / 2, y: r.midY - size / 2, width: size, height: size)
            bead.radius = size / 2
            bead.style = "bead"
            parts.append(bead)
        }
        return parts
    }

    /// The glass outside the rims' cuts (the L's round outer corner): masked off, so Apple's
    /// glass, made of rounded rects, follows the corner the rim and the tint draw.
    private func maskCuts() {
        guard let layer = bodies.container.layer else { return }
        let cuts = rims.compactMap { rim in rim.outerCut.map { (rim.frame.origin, $0) } }
        guard !cuts.isEmpty else {
            layer.mask = nil
            return
        }
        let bounds = layer.bounds
        let mask = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = bounds
        mask.fillRule = .evenOdd
        let path = CGMutablePath()
        path.addRect(bounds)
        // the rims are in the flipped view's coordinates: y down; the container may not be flipped
        let flip = bodies.container.isFlipped ? .identity : CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        for (origin, cut) in cuts {
            path.addPath(cut, transform: CGAffineTransform(translationX: origin.x, y: origin.y).concatenating(flip))
        }
        mask.path = path
        layer.mask = mask
    }

    /// The shapes in groups of those that overlap, each group one rim.
    private static func overlapping(_ shapes: [GlassShape]) -> [[GlassShape]] {
        var groups: [[GlassShape]] = []
        for shape in shapes {
            let joined = groups.indices.filter { groups[$0].contains { $0.rect.intersects(shape.rect) } }
            var group = joined.flatMap { groups[$0] } + [shape]
            for index in joined.reversed() { groups.remove(at: index) }
            group.sort { $0.rect.minX < $1.rect.minX }
            groups.append(group)
        }
        return groups
    }

    /// The neck of liquid from a lens's drop to the lens, as skylandbar's shader drew it: one
    /// thin tube of glass between their middles, which the container melts into both, so it
    /// is thick where it joins them and thin in between; it thins as the drop shrinks and is
    /// gone before the drop. One shape: no beads, each with its own rim and color split.
    private func neck(from tail: NSRect, to lens: GlassShape) -> GlassShape? {
        let head = lens.rect, headR = Double(head.height) / 2
        let life = min(1, max(0, Double(tail.height / max(head.height, 1))))
        let neckLife = min(1, max(0, (life - 0.6) / 0.35)), smooth = neckLife * neckLife * (3 - 2 * neckLife)
        let left = min(tail.midX, head.midX), right = max(tail.midX, head.midX)
        // a neck only while the lens is near its drop: a long jump stretched it into a wire
        // across the bar; it thins as they part and snaps at 3 lens heights
        let reach = 1 - Double(right - left) / (6 * headR)
        guard right - left > headR, reach > 0 else { return nil }
        let thickness = 2 * headR * 0.22 * smooth * min(1, reach * 2)
        guard thickness > 1.5 else { return nil }
        let y = (tail.midY + head.midY) / 2
        var neck = lens
        neck.rect = NSRect(x: left, y: y - thickness / 2, width: right - left, height: thickness)
        neck.radius = thickness / 2
        neck.style = "neck"
        neck.tail = nil
        return neck
    }

    /// `keep`: views no shape needs now are hidden, not removed: a drop that comes and goes
    /// every lens move took a new glass view, which showed Apple's frosted look for a frame
    /// before skylandbar's (a flash where the lens left)
    private func place(_ shapes: [GlassShape], in holder: NSView, views: inout [NSView], keep: Bool = false) {
        if keep {
            for (index, view) in views.enumerated() { view.isHidden = index >= shapes.count }
        } else {
            while views.count > shapes.count { views.removeLast().removeFromSuperview() }
        }
        while views.count < shapes.count {
            let glass = Glass.makeView()
            holder.addSubview(glass)
            views.append(glass)
        }
        for (glass, shape) in zip(views, shapes) {
            glass.frame = shape.rect
            Glass.update(glass, style: shape.style, tint: shape.tint, cornerRadius: shape.radius)
            // a new tint rebuilds Apple's glass filter at the next layout: now, so skylandbar's
            // values (GlassLook, right after) go on the new one; else a frame of the frosted look
            glass.layoutSubtreeIfNeeded()
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

// MARK: flat

/// `glass_engine = flat` (themes/glyph.toml): each glass shape an opaque panel in its tint
/// with a thin line and a faint dot grid; a lens (the selection) and a hover drop a pill in
/// their tint, the lens outlined. Line and dots are the tint's contrast color (white on a
/// dark tint, black on a light one), so a theme only sets the tints. Nothing captured.
final class FlatGlass: GlassRenderer {
    private let flat = FlatGlassView()
    var view: NSView { flat }
    let failed = false

    func update(_ shapes: [GlassShape], settings: GlassSettings, window: NSWindow) {
        flat.shapes = shapes
    }
}

private final class FlatGlassView: NSView {
    var shapes: [GlassShape] = [] { didSet { if shapes != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true } // the shapes' coordinates
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // the items' view takes the mouse

    override func draw(_ dirtyRect: NSRect) {
        for shape in shapes {
            let tint = Fonts.color(shape.tint)
            let light = (0.299 * shape.tint.red + 0.587 * shape.tint.green + 0.114 * shape.tint.blue) > 0.5
            let ink = light ? NSColor.black : NSColor.white
            let radius = min(CGFloat(shape.radius), shape.rect.height / 2)
            let path = NSBezierPath(roundedRect: shape.rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            tint.setFill()
            path.fill()
            switch shape.style {
                case "lens":
                    ink.withAlphaComponent(0.85).setStroke()
                    path.lineWidth = 1.5
                    path.stroke()
                case "hover":
                    break
                default:
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    ink.withAlphaComponent(0.08).setFill()
                    let pitch: CGFloat = 6, dot: CGFloat = 1.2
                    for y in stride(from: shape.rect.minY + pitch / 2, to: shape.rect.maxY, by: pitch) {
                        for x in stride(from: shape.rect.minX + pitch / 2, to: shape.rect.maxX, by: pitch) {
                            NSBezierPath(ovalIn: NSRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)).fill()
                        }
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    ink.withAlphaComponent(0.16).setStroke()
                    path.lineWidth = 1
                    path.stroke()
            }
        }
    }
}
