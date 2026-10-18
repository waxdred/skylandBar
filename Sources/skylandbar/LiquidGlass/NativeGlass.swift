import AppKit
import SkylandBarCore
import SwiftUI

// skylandbar's `native` glass engine (macOS 26): Apple's Liquid Glass through SwiftUI, the
// shapes in GlassEffectContainers. The window server draws it, live, with no capture: what
// is behind refracts as it moves, and protected videos play. Lenses and hover drops are
// glass of their own, over the groups' glass (never melted into it), and SwiftUI animates
// them to their item on a spring: the bar gives this engine its targets, not LensMotion's
// frames. Compiled with the macOS 26 SDK only (SwiftUI 7): an older SDK leaves it out.

enum NativeGlassSupport {
    static var available: Bool {
        #if canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    static func make() -> GlassRenderer? {
        #if canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) { return NativeGlass() }
        #endif
        return nil
    }
}

#if canImport(SwiftUI, _version: 7.0)

    @available(macOS 26.0, *)
    final class NativeGlass: GlassRenderer {
        let view: NSView
        let failed = false
        var animatesLenses: Bool { true }
        private let model = NativeGlassModel()

        init() {
            let host = NSHostingView(rootView: NativeGlassLayer(model: model))
            host.sizingOptions = [] // the window sizes it, never the other way
            view = host
        }

        func update(_ shapes: [GlassShape], settings: GlassSettings, window: NSWindow) {
            let isDrop = { (style: String) in style == "lens" || style == "hover" }
            let bodies = shapes.filter { !isDrop($0.style) }.enumerated().map { NativeShape("body-\($0.offset)", $0.element) }
            let drops = shapes.filter { isDrop($0.style) }.enumerated().map { NativeShape("\($0.element.style)-\($0.offset)", $0.element) }
            if bodies != model.bodies || settings.spacing != model.spacing {
                var still = Transaction() // the groups follow the layout at once
                still.disablesAnimations = true
                withTransaction(still) {
                    model.bodies = bodies
                    model.spacing = settings.spacing
                }
            }
            if drops != model.drops {
                // to a new item on a spring; with the fingers (a workspace swipe), close behind them
                let motion: Animation? = settings.reduceMotion ? nil
                    : settings.following ? .interactiveSpring(response: 0.12, dampingFraction: 0.9)
                    : .spring(response: settings.lensResponse, dampingFraction: 1 - 0.6 * settings.lensBounce)
                withAnimation(motion) { model.drops = drops }
            }
        }
    }

    @available(macOS 26.0, *)
    struct NativeShape: Identifiable, Equatable {
        let id: String
        var rect: CGRect
        var radius: Double
        var tint: ARGB
        var clear: Bool
        var hover: Bool

        init(_ id: String, _ shape: GlassShape) {
            self.id = id
            rect = shape.rect
            radius = min(shape.radius, Double(min(shape.rect.width, shape.rect.height)) / 2)
            tint = shape.tint
            clear = shape.style == "clear" || shape.style == "hover"
            hover = shape.style == "hover"
        }

        var glass: SwiftUI.Glass {
            var glass: SwiftUI.Glass = clear ? .clear : .regular
            if tint.alpha > 0 {
                let color = Fonts.color(tint)
                glass = glass.tint(Color(nsColor: hover ? color.withAlphaComponent(color.alphaComponent * 0.5) : color))
            }
            return glass
        }
    }

    @available(macOS 26.0, *)
    final class NativeGlassModel: ObservableObject {
        @Published var bodies: [NativeShape] = []
        @Published var drops: [NativeShape] = []
        @Published var spacing = 0.0
    }

    @available(macOS 26.0, *)
    struct NativeGlassLayer: View {
        @ObservedObject var model: NativeGlassModel

        var body: some View {
            ZStack(alignment: .topLeading) {
                // the groups: shapes closer than glass_spacing melt into one
                GlassEffectContainer(spacing: model.spacing) { shapes(model.bodies) }
                // a selection, a hover drop: glass over the group's glass, its own shape
                GlassEffectContainer(spacing: 0) { shapes(model.drops) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false) // the items' view takes the mouse
        }

        private func shapes(_ list: [NativeShape]) -> some View {
            ZStack(alignment: .topLeading) {
                ForEach(list) { shape in
                    Color.clear
                        .frame(width: shape.rect.width, height: shape.rect.height)
                        .glassEffect(shape.glass, in: RoundedRectangle(cornerRadius: shape.radius, style: .continuous))
                        .offset(x: shape.rect.minX, y: shape.rect.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

#endif
