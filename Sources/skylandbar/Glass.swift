import AppKit
import SkylandBarCore

/// Liquid Glass (`glass=on|clear` on the bar, popups and backgrounds): NSGlassEffectView on
/// macOS 26 built with Xcode 26, a blurred NSVisualEffectView before.
enum Glass {
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
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = Fonts.color(tint).cgColor
    }
}
