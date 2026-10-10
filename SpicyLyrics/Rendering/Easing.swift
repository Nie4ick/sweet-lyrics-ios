import Foundation

/// CSS timing functions, so CSS transitions from Spicy Lyrics' stylesheets can be replayed exactly.
enum Easing {
    case cubicBezier(Double, Double, Double, Double)
    /// CSS `linear(...)`: points `(progress, value)`, interpolated piecewise linearly.
    case linearPoints([(Double, Double)])

    /// CSS `ease`.
    static let ease = Easing.cubicBezier(0.25, 0.1, 0.25, 1)

    func value(at t: Double) -> Double {
        let x = clamp(t, 0, 1)
        switch self {
        case .cubicBezier(let x1, let y1, let x2, let y2):
            return Self.bezier(x, x1, y1, x2, y2)
        case .linearPoints(let points):
            guard var previous = points.first else { return x }
            if x <= previous.0 { return previous.1 }
            for point in points.dropFirst() {
                if x <= point.0 {
                    let span = point.0 - previous.0
                    return span > 0 ? previous.1 + (point.1 - previous.1) * (x - previous.0) / span : point.1
                }
                previous = point
            }
            return previous.1
        }
    }

    /// Solves the bezier's x(t) = x by Newton's method with a bisection fallback, then returns y(t).
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return sampleY(t) }
            let d = slopeX(t)
            if abs(d) < 1e-6 { break }
            t -= error / d
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<30 {
            let value = sampleX(t)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sampleY(t)
    }
}

/// A CSS-style transition of one number: retargeting starts a new transition from the current value.
struct Tween {
    private(set) var value: Double
    private var from: Double
    private var to: Double
    private var startedAt: Double = 0
    private let duration: Double
    private let easing: Easing

    init(_ value: Double, duration: Double, easing: Easing) {
        self.value = value
        from = value
        to = value
        self.duration = duration
        self.easing = easing
    }

    var isSettled: Bool { value == to }

    /// Moves toward `target` at media time `now`; returns the current value.
    @discardableResult
    mutating func update(to target: Double, now: Double, snap: Bool = false) -> Double {
        if snap {
            value = target
            from = target
            to = target
            return value
        }
        if target != to {
            from = value
            to = target
            startedAt = now
        }
        if value != to {
            let progress = duration > 0 ? (now - startedAt) / duration : 1
            value = progress >= 1 ? to : from + (to - from) * easing.value(at: progress)
        }
        return value
    }
}
