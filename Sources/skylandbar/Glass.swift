import AppKit
import SkylandBarCore

/// Liquid Glass (`glass=on|clear` on the bar, popups and backgrounds): NSGlassEffectView on
/// macOS 26, a blurred NSVisualEffectView before. Looked up at run time (NSClassFromString,
/// key-value coding): a build with an SDK older than macOS 26 (Homebrew's, CI's) still has
/// Apple's glass on macOS 26.
enum Glass {
    static let effectView = NSClassFromString("NSGlassEffectView") as? NSView.Type
    static let containerView = NSClassFromString("NSGlassEffectContainerView") as? NSView.Type

    static func makeView() -> NSView {
        if let effectView { return effectView.init(frame: .zero) }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    /// The parent of a window's item glass views: on macOS 26 an NSGlassEffectContainerView,
    /// which renders them together (fewer passes) and merges the ones closer than its
    /// spacing, as Apple asks for groups of glass; a plain view before. (container, holder):
    /// the glass views go in the holder, the container in the window.
    static func makeContainer() -> (container: NSView, holder: NSView) {
        let holder = FlippedHolder()
        holder.autoresizingMask = [.width, .height]
        if let containerView {
            let container = containerView.init(frame: .zero)
            holder.frame = container.bounds
            container.setValue(holder, forKey: "contentView")
            return (container, holder)
        }
        return (holder, holder)
    }

    /// The merging distance of the container a holder is in.
    static func setSpacing(_ holder: NSView, _ spacing: Double) {
        guard let containerView, let container = holder.superview, container.isKind(of: containerView),
              (container.value(forKey: "spacing") as? Double) != spacing else { return }
        container.setValue(spacing, forKey: "spacing")
    }

    /// `style`: regular | clear; `tint`: the background's color.
    static func update(_ view: NSView, style: String, tint: ARGB, cornerRadius: Double) {
        if let effectView, view.isKind(of: effectView) {
            view.setValue(cornerRadius, forKey: "cornerRadius")
            view.setValue(tint.alpha > 0 ? Fonts.color(tint) : nil, forKey: "tintColor")
            view.setValue(style == "clear" ? 1 : 0, forKey: "style") // NSGlassEffectView.Style: regular 0, clear 1
            return
        }
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous // Apple's shapes: no circular corners
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = Fonts.color(tint).cgColor
    }
}

// MARK: skylandbar's look on Apple's glass

/// Apple's glass draws what is behind through a private filter (`glassBackground`) on a
/// CABackdropLayer (in each NSGlassEffectView, or in the container rendering them together), set for a frosted look: a lot of blur, a
/// narrow refraction, at half resolution. skylandbar sets its own values there: a sharp
/// middle, what is behind bent hard along the edge, colors split a little, from the bar's
/// glass_refraction / glass_blur / glass_saturation. Still the window server's glass: live,
/// no capture. Looked up by name; nothing changes if a macOS has it otherwise.
enum GlassLook {
    /// Under `view` (a glass view, or the container that renders its glass views together):
    /// each glass backdrop gets skylandbar's values. Again on the next turn of the run loop,
    /// for the layers SwiftUI makes after a layout.
    /// `height`: the smallest shape's, which the bent band keeps within (a quarter of it, as
    /// skylandbar's own shader did: a thin bar bent all over was unreadable).
    /// `lift`: nil for a group's glass; a lens's (0 at rest, 1 moving fast): thicker glass,
    /// what is behind bent over a wider band and lighter, more so while it moves (as
    /// skylandbar's own shader did).
    static func apply(_ view: NSView, settings: GlassSettings, height: Double, lift: Double? = nil) {
        set(view, settings, height, lift)
        DispatchQueue.main.async { set(view, settings, height, lift) }
    }

    private static func set(_ view: NSView, _ settings: GlassSettings, _ height: Double, _ lift: Double?) {
        guard let root = view.layer else { return }
        var values: [String: Double]
        if let lift { // a drop: half its height bent, its middle magnified, a light of its own
            let band = max(2, height * (0.34 + 0.1 * lift))
            values = [
                "inputInnerRefractionAmount": -(1.8 + 2.4 * lift) * band, "inputInnerRefractionHeight": band,
                "inputAberrationAmount": (0.3 + 0.3 * lift) * band, "inputAberrationHeight": band,
                "inputBlurRadius": settings.blur * 0.3,
                "inputFaceColorMatrixWhite": 1.32 + 0.1 * lift, "inputFaceColorMatrixBlack": 0.1,
                "inputKeyFillHighlightAmount": 0.9 + 0.3 * lift,
            ]
        } else {
            let band = min(2.3 * settings.refraction, max(2, height / 4))
            values = [
                "inputInnerRefractionAmount": -2.5 * band, "inputInnerRefractionHeight": band,
                "inputAberrationAmount": 0.2 * band, "inputAberrationHeight": band,
                "inputBlurRadius": settings.blur / 2,
            ]
        }
        values.merge([
            "inputBlurOpacity0": 0.1, "inputBlurOpacity1": 0.1, "inputBlurOpacity2": 0.1, "inputBlurOpacity3": 0.1,
            "inputBlurFillNormalOpacity": 0, "inputBlurFillDarkenOpacity": 0, "inputBlurFillLightenOpacity": 0, "inputBleedAmount": 0,
            "inputFaceColorMatrixSaturation": 1 + (settings.saturation - 1) * 0.6,
            // Apple's luminance cap (0.5) kept: without it a bright wallpaper burned the text out
        ]) { mine, _ in mine }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for backdrop in backdrops(root) {
            if (backdrop.value(forKey: "scale") as? Double) != 1 { backdrop.setValue(1, forKey: "scale") } // Apple's: half resolution
            for (key, value) in values where (backdrop.value(forKeyPath: "filters.glassBackground.\(key)") as? Double) != value {
                backdrop.setValue(value, forKeyPath: "filters.glassBackground.\(key)")
            }
        }
        CATransaction.commit()
    }

    private static func backdrops(_ layer: CALayer) -> [CALayer] {
        var found: [CALayer] = []
        if NSStringFromClass(type(of: layer)) == "CABackdropLayer",
           (layer.filters as? [NSObject])?.contains(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) == true
        {
            found.append(layer)
        }
        for sublayer in layer.sublayers ?? [] { found += backdrops(sublayer) }
        return found
    }
}

/// Glass views are placed in the bar view's flipped coordinates.
private final class FlippedHolder: NSView {
    override var isFlipped: Bool { true }
}
