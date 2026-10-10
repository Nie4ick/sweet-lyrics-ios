import Foundation

/// Analytic damped spring. Port of Spicy Lyrics' `modules/Spring.ts`, which is itself a port of
/// https://github.com/Fraktality/spr (MIT, Copyright (c) Fraktality).
struct Spring {
    private static let sleepOffsetSqLimit: Double = (1.0 / 3840.0) * (1.0 / 3840.0)
    private static let sleepVelocitySqLimit: Double = 1e-2 * 1e-2
    private static let eps = 1e-5

    var dampingRatio: Double
    var frequency: Double
    private(set) var goal: Double
    private(set) var position: Double
    private(set) var velocity: Double = 0

    init(_ start: Double, frequency: Double, damping: Double, goal: Double? = nil) {
        self.dampingRatio = damping
        self.frequency = frequency
        self.goal = goal ?? start
        self.position = start
    }

    mutating func setGoal(_ goal: Double, replacePosition: Bool = false) {
        self.goal = goal
        if replacePosition {
            position = goal
            velocity = 0
        }
    }

    var canSleep: Bool {
        if velocity * velocity > Self.sleepVelocitySqLimit { return false }
        let offset = position - goal
        return offset * offset <= Self.sleepOffsetSqLimit
    }

    @discardableResult
    mutating func step(_ dt: Double) -> Double {
        let d = dampingRatio
        let f = frequency * 2 * .pi
        let g = goal
        var p = position
        var v = velocity

        if d == 1 {
            let q = exp(-f * dt)
            let w = dt * q
            let c0 = q + w * f
            let c2 = q - w * f
            let c3 = w * f * f
            let o = p - g
            p = o * c0 + v * w + g
            v = v * c2 - o * c3
        } else if d < 1 {
            let q = exp(-d * f * dt)
            let c = (1 - d * d).squareRoot()
            let i = cos(dt * f * c)
            let j = sin(dt * f * c)

            let z: Double
            if c > Self.eps {
                z = j / c
            } else {
                let a = dt * f
                z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6
            }

            let y: Double
            if f * c > Self.eps {
                y = j / (f * c)
            } else {
                let b = f * c
                y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6
            }

            let o = p - g
            p = (o * (i + z * d) + v * y) * q + g
            v = (v * (i - z * d) - o * (z * f)) * q
        } else {
            let c = (d * d - 1).squareRoot()
            let r1 = -f * (d + c)
            let r2 = -f * (d - c)
            let ec1 = exp(r1 * dt)
            let ec2 = exp(r2 * dt)
            let o = p - g
            let co2 = (v - o * r1) / (2 * f * c)
            let co1 = ec1 * (o - co2)
            p = co1 + co2 * ec2 + g
            v = co1 * r1 + co2 * ec2 * r2
        }

        if canSleepAfter(p: p, v: v, g: g) {
            p = g
            v = 0
        }
        position = p
        velocity = v
        return p
    }

    private func canSleepAfter(p: Double, v: Double, g: Double) -> Bool {
        if v * v > Self.sleepVelocitySqLimit { return false }
        let o = p - g
        return o * o <= Self.sleepOffsetSqLimit
    }
}

/// Natural cubic spline through a handful of control points, matching the `cubic-spline` npm
/// package that Spicy Lyrics uses for its animation curves.
struct CubicSpline {
    private let xs: [Double]
    private let ys: [Double]
    private let ks: [Double]

    init(_ points: [(Double, Double)]) {
        xs = points.map(\.0)
        ys = points.map(\.1)
        ks = CubicSpline.derivatives(xs: xs, ys: ys)
    }

    func at(_ x: Double) -> Double {
        guard xs.count > 1 else { return ys.first ?? 0 }
        var i = 1
        while i < xs.count - 1 && xs[i] < x { i += 1 }
        let x0 = xs[i - 1], x1 = xs[i]
        let y0 = ys[i - 1], y1 = ys[i]
        let h = x1 - x0
        let t = (x - x0) / h
        let a = ks[i - 1] * h - (y1 - y0)
        let b = -ks[i] * h + (y1 - y0)
        return (1 - t) * y0 + t * y1 + t * (1 - t) * (a * (1 - t) + b * t)
    }

    /// Solves the tridiagonal system for the knot derivatives of a natural spline.
    private static func derivatives(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        var a = Array(repeating: 0.0, count: n)
        var b = Array(repeating: 0.0, count: n)
        var c = Array(repeating: 0.0, count: n)
        var r = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            if i == 0 {
                let h = xs[1] - xs[0]
                b[i] = 2 / h
                c[i] = 1 / h
                r[i] = 3 * (ys[1] - ys[0]) / (h * h)
            } else if i == n - 1 {
                let h = xs[i] - xs[i - 1]
                a[i] = 1 / h
                b[i] = 2 / h
                r[i] = 3 * (ys[i] - ys[i - 1]) / (h * h)
            } else {
                let h0 = xs[i] - xs[i - 1]
                let h1 = xs[i + 1] - xs[i]
                a[i] = 1 / h0
                b[i] = 2 * (1 / h0 + 1 / h1)
                c[i] = 1 / h1
                r[i] = 3 * ((ys[i] - ys[i - 1]) / (h0 * h0) + (ys[i + 1] - ys[i]) / (h1 * h1))
            }
        }

        // Thomas algorithm.
        for i in 1..<n {
            let m = a[i] / b[i - 1]
            b[i] -= m * c[i - 1]
            r[i] -= m * r[i - 1]
        }
        var k = Array(repeating: 0.0, count: n)
        k[n - 1] = r[n - 1] / b[n - 1]
        if n >= 2 {
            for i in stride(from: n - 2, through: 0, by: -1) {
                k[i] = (r[i] - c[i] * k[i + 1]) / b[i]
            }
        }
        return k
    }
}

@inline(__always) func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

/// d3-ease `easeSinOut`.
@inline(__always) func easeSinOut(_ t: Double) -> Double {
    sin(t * .pi / 2)
}
