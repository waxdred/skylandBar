import AppKit
import SkylandBarCore

/// Liquid Glass (`glass=on|clear` on the bar, popups and backgrounds): NSGlassEffectView on
/// macOS 26 built with Xcode 26, a blurred NSVisualEffectView before.
enum Glass {
    /// Which glass this bar draws, and why: said at start
    static var engine: String {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) { return "Liquid Glass (NSGlassEffectView)" }
            return "blur (NSVisualEffectView): Liquid Glass needs macOS 26, this is macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
            return "blur (NSVisualEffectView): Liquid Glass needs a build with Xcode 26 (sudo xcode-select -s /Applications/Xcode.app)"
        #endif
    }

    static func makeView() -> NSView {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) { return NSGlassEffectView() }
        #endif
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
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let container = NSGlassEffectContainerView()
                holder.frame = container.bounds
                container.contentView = holder
                return (container, holder)
            }
        #endif
        return (holder, holder)
    }

    /// The merging distance of the container a holder is in.
    static func setSpacing(_ holder: NSView, _ spacing: Double) {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *), let container = holder.superview as? NSGlassEffectContainerView,
               container.spacing != spacing
            {
                container.spacing = spacing
            }
        #endif
    }

    /// `style`: regular | clear; `tint`: the background's color.
    static func update(_ view: NSView, style: String, tint: ARGB, cornerRadius: Double) {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
                glass.cornerRadius = cornerRadius
                glass.tintColor = tint.alpha > 0 ? Fonts.color(tint) : nil
                glass.style = style == "clear" ? .clear : .regular
                return
            }
        #endif
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
