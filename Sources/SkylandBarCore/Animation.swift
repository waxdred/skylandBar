import Foundation

// `--animate <curve> <duration> --set ...`: the numbers and colors the following commands
// change go there over `duration` frames (60 a second) along the curve; everything else
// changes at once. The model keeps the targets; what is drawn is `blend(from, to, t)`.

public enum Curve: String, CaseIterable {
    case linear, quadratic, tanh, sin, exp, circ

    /// 0 -> 0, 1 -> 1
    public func value(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        switch self {
            case .linear: return t
            case .quadratic: return t * t
            case .tanh: return tanhCurve(t)
            case .sin: return sinCurve(t)
            case .exp: return expCurve(t)
            case .circ: return (1 - (1 - t) * (1 - t)).squareRoot()
        }
    }
}

// out here, where tanh, sin and exp are the math functions and not the cases
private func tanhCurve(_ t: Double) -> Double { tanh(3 * t) / tanh(3) }
private func sinCurve(_ t: Double) -> Double { sin(t * .pi / 2) }
private func expCurve(_ t: Double) -> Double { t * exp(t - 1) }

public let framesPerSecond = 60.0

/// One property set on its way from `from` to the model's value.
struct Transition<Props> {
    var from: Props
    var start: Double
    var duration: Double
    var curve: Curve

    func progress(at now: Double) -> Double {
        duration <= 0 ? 1 : curve.value((now - start) / duration)
    }

    func isDone(at now: Double) -> Bool { now - start >= duration }
}

private func mixOptional(_ a: Double?, _ b: Double?, _ t: Double) -> Double? {
    guard let a, let b else { return b }
    return mix(a, b, t)
}

extension ShadowProps {
    static func blend(_ a: ShadowProps, _ b: ShadowProps, _ t: Double) -> ShadowProps {
        var r = b
        r.color = .mix(a.color, b.color, t)
        r.angle = mix(a.angle, b.angle, t)
        r.distance = mix(a.distance, b.distance, t)
        return r
    }
}

extension ImageProps {
    static func blend(_ a: ImageProps, _ b: ImageProps, _ t: Double) -> ImageProps {
        var r = b
        r.scale = mix(a.scale, b.scale, t)
        r.cornerRadius = mix(a.cornerRadius, b.cornerRadius, t)
        r.borderWidth = mix(a.borderWidth, b.borderWidth, t)
        r.borderColor = .mix(a.borderColor, b.borderColor, t)
        r.paddingLeft = mix(a.paddingLeft, b.paddingLeft, t)
        r.paddingRight = mix(a.paddingRight, b.paddingRight, t)
        r.yOffset = mix(a.yOffset, b.yOffset, t)
        r.shadow = .blend(a.shadow, b.shadow, t)
        return r
    }
}

extension BackgroundProps {
    static func blend(_ a: BackgroundProps, _ b: BackgroundProps, _ t: Double) -> BackgroundProps {
        var r = b
        r.color = .mix(a.color, b.color, t)
        r.borderColor = .mix(a.borderColor, b.borderColor, t)
        r.borderWidth = mix(a.borderWidth, b.borderWidth, t)
        r.height = mix(a.height, b.height, t)
        r.cornerRadius = a.cornerRadius < 0 || b.cornerRadius < 0 ? b.cornerRadius : mix(a.cornerRadius, b.cornerRadius, t) // concentric: at once
        r.paddingLeft = mix(a.paddingLeft, b.paddingLeft, t)
        r.paddingRight = mix(a.paddingRight, b.paddingRight, t)
        r.xOffset = mix(a.xOffset, b.xOffset, t)
        r.yOffset = mix(a.yOffset, b.yOffset, t)
        r.image = .blend(a.image, b.image, t)
        r.shadow = .blend(a.shadow, b.shadow, t)
        return r
    }
}

extension TextProps {
    static func blend(_ a: TextProps, _ b: TextProps, _ t: Double) -> TextProps {
        var r = b
        r.color = .mix(a.color, b.color, t)
        r.highlightColor = .mix(a.highlightColor, b.highlightColor, t)
        r.paddingLeft = mix(a.paddingLeft, b.paddingLeft, t)
        r.paddingRight = mix(a.paddingRight, b.paddingRight, t)
        r.yOffset = mix(a.yOffset, b.yOffset, t)
        if a.font.family == b.font.family && a.font.style == b.font.style { r.font.size = mix(a.font.size, b.font.size, t) }
        r.width = mixOptional(a.width, b.width, t)
        r.background = .blend(a.background, b.background, t)
        r.shadow = .blend(a.shadow, b.shadow, t)
        return r
    }
}

extension ItemProps {
    static func blend(_ a: ItemProps, _ b: ItemProps, _ t: Double) -> ItemProps {
        var r = b
        r.yOffset = mix(a.yOffset, b.yOffset, t)
        r.width = mixOptional(a.width, b.width, t)
        r.icon = .blend(a.icon, b.icon, t)
        r.label = .blend(a.label, b.label, t)
        r.background = .blend(a.background, b.background, t)
        r.popup.background = .blend(a.popup.background, b.popup.background, t)
        r.popup.yOffset = mix(a.popup.yOffset, b.popup.yOffset, t)
        r.popup.height = mix(a.popup.height, b.popup.height, t)
        r.graph.color = .mix(a.graph.color, b.graph.color, t)
        r.slider.percentage = mix(a.slider.percentage, b.slider.percentage, t)
        r.slider.width = mix(a.slider.width, b.slider.width, t)
        r.slider.highlightColor = .mix(a.slider.highlightColor, b.slider.highlightColor, t)
        r.slider.background = .blend(a.slider.background, b.slider.background, t)
        r.slider.knob = .blend(a.slider.knob, b.slider.knob, t)
        r.alias.color = .mix(a.alias.color, b.alias.color, t)
        r.alias.scale = mix(a.alias.scale, b.alias.scale, t)
        return r
    }
}

extension BarProps {
    static func blend(_ a: BarProps, _ b: BarProps, _ t: Double) -> BarProps {
        var r = b
        r.color = .mix(a.color, b.color, t)
        r.borderColor = .mix(a.borderColor, b.borderColor, t)
        r.borderWidth = mix(a.borderWidth, b.borderWidth, t)
        r.height = mix(a.height, b.height, t)
        r.margin = mix(a.margin, b.margin, t)
        r.yOffset = mix(a.yOffset, b.yOffset, t)
        r.cornerRadius = mix(a.cornerRadius, b.cornerRadius, t)
        r.blurRadius = mix(a.blurRadius, b.blurRadius, t)
        r.glassSpacing = mix(a.glassSpacing, b.glassSpacing, t)
        r.glassRefraction = mix(a.glassRefraction, b.glassRefraction, t)
        r.glassBlur = mix(a.glassBlur, b.glassBlur, t)
        r.glassSaturation = mix(a.glassSaturation, b.glassSaturation, t)
        r.paddingLeft = mix(a.paddingLeft, b.paddingLeft, t)
        r.paddingRight = mix(a.paddingRight, b.paddingRight, t)
        r.notchWidth = mix(a.notchWidth, b.notchWidth, t)
        r.notchOffset = mix(a.notchOffset, b.notchOffset, t)
        return r
    }
}
