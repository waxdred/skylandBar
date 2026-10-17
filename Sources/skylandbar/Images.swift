import AppKit
import SkylandBarCore

/// The images of `background.image`: a file, `app.<bundle id or name>` (the app's icon)
/// or `media.artwork` (the now playing artwork, from the media events).
enum Images {
    /// misses too, so a wrong path is not looked up at every layout
    private static var cache: [String: NSImage?] = [:]
    static var artwork: NSImage?

    static func image(_ string: String) -> NSImage? {
        if string == "media.artwork" { return artwork }
        if let cached = cache[string] { return cached }
        let image = string.hasPrefix("app.") ? appIcon(String(string.dropFirst(4)))
            : NSImage(contentsOfFile: (string as NSString).expandingTildeInPath)
        cache[string] = image
        return image
    }

    private static func appIcon(_ app: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: app) { return workspace.icon(forFile: url.path) }
        if let running = workspace.runningApplications.first(where: { $0.localizedName == app }), let icon = running.icon {
            return icon
        }
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"] {
            let path = "\(folder)/\(app).app"
            if FileManager.default.fileExists(atPath: path) { return workspace.icon(forFile: path) }
        }
        return nil
    }

    /// The size it is drawn at: its own (app icons 32 points) times `scale`.
    static func size(_ props: ImageProps) -> NSSize {
        guard props.isShown, let image = image(props.string) else { return .zero }
        return NSSize(width: image.size.width * props.scale, height: image.size.height * props.scale)
    }

    /// The width it takes in a layout, with its paddings.
    static func width(_ props: ImageProps) -> Double {
        let size = size(props)
        return size.width > 0 ? props.paddingLeft + size.width + props.paddingRight : 0
    }

    /// `image` drawn into `rect` of a flipped view, rounded, bordered, tinted with `tint`
    /// when it has an alpha.
    static func draw(_ image: NSImage, in rect: NSRect, cornerRadius: Double = 0, borderWidth: Double = 0,
                     borderColor: ARGB = .clear, tint: ARGB = .clear)
    {
        var drawn = image
        if tint.alpha > 0 {
            drawn = NSImage(size: image.size, flipped: false) { bounds in
                image.draw(in: bounds)
                Fonts.color(tint).set()
                bounds.fill(using: .sourceAtop)
                return true
            }
        }
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        if radius > 0 { path.addClip() }
        drawn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        if borderWidth > 0 {
            Fonts.color(borderColor).setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }
}
