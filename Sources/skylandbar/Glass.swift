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

/// Glass views are placed in the bar view's flipped coordinates.
private final class FlippedHolder: NSView {
    override var isFlipped: Bool { true }
}
