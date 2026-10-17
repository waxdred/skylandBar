import Foundation

/// How a selection lens (`background.glass = "lens"`) moves, as Apple's tab bars: when it
/// goes to another item, it slides there on a spring (`glass_lens_response` seconds,
/// `glass_lens_bounce` from 0, no overshoot, to 1), stretching along its way the faster it
/// goes (`glass_lens_stretch`, 0: none), like a drop; a lens that appears grows out of 70 %.
/// The spring keeps its speed when the target changes on the way. Rects in points.
public final class LensMotion {
    public var response = 0.35
    public var bounce = 0.3
    public var stretch = 1.0

    private struct Spring {
        var value: Double
        var velocity = 0.0
    }

    /// center x, center y, width, height of each lens
    private var lenses: [[Spring]] = []
    private var last: Double?

    public init() {}

    public var isMoving: Bool { lenses.contains { $0.contains { abs($0.velocity) > 0 } } }

    /// The rects to draw for these targets at `now` (seconds), and whether they still move.
    public func step(_ targets: [Box], now: Double, reduceMotion: Bool = false) -> (rects: [Box], moving: Bool) {
        let goals = targets.map { [$0.x + $0.width / 2, $0.y + $0.height / 2, $0.width, $0.height] }
        defer { last = now }
        if reduceMotion || response <= 0 {
            lenses = goals.map { $0.map { Spring(value: $0) } }
            return (targets, false)
        }
        // the lenses there were keep going; a new one grows from 70 % of its size
        lenses = goals.indices.map { index in
            if index < lenses.count { return lenses[index] }
            let goal = goals[index]
            return [Spring(value: goal[0]), Spring(value: goal[1]), Spring(value: goal[2] * 0.7), Spring(value: goal[3] * 0.7)]
        }
        let dt = min(max(now - (last ?? now), 0), 1.0 / 20)
        let stiffness = pow(2 * Double.pi / response, 2)
        let damping = 2 * max(0.05, 1 - bounce) * stiffness.squareRoot()
        let steps = max(1, Int((dt * 240).rounded(.up))) // small steps: stable at any frame rate
        let h = dt / Double(steps)
        var moving = false
        var rects: [Box] = []
        for index in lenses.indices {
            for component in 0 ..< 4 {
                var spring = lenses[index][component]
                let goal = goals[index][component]
                for _ in 0 ..< steps {
                    spring.velocity += (-stiffness * (spring.value - goal) - damping * spring.velocity) * h
                    spring.value += spring.velocity * h
                }
                if abs(spring.value - goal) < 0.2 && abs(spring.velocity) < 2 {
                    spring = Spring(value: goal) // there: snapped, at rest
                } else {
                    moving = true
                }
                lenses[index][component] = spring
            }
            let lens = lenses[index]
            // a drop: longer along its way, a little thinner, the faster it goes
            let speed = abs(lens[0].velocity)
            let longer = min(speed * 0.045 * stretch, lens[2].value * 0.35)
            let thinner = min(speed * 0.012 * stretch, lens[3].value * 0.15)
            let width = lens[2].value + longer, height = lens[3].value - thinner
            rects.append(Box(x: lens[0].value - width / 2, y: lens[1].value - height / 2, width: width, height: height))
        }
        return (rects, moving)
    }
}
