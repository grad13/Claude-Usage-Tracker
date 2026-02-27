// meta: created=2026-02-26 updated=2026-02-26 checked=2026-02-26
import SwiftUI

struct MiniUsageGraph: View {
    let history: [UsageStore.DataPoint]
    let windowSeconds: TimeInterval
    let resetsAt: Date?
    let areaColor: Color
    let areaOpacity: Double
    let divisions: Int
    let chartWidth: CGFloat
    let isLoggedIn: Bool

    private static let bgColor = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
    private static let bgColorSignedOut = Color(red: 0x3A/255, green: 0x10/255, blue: 0x10/255)
    private static let tickColor = Color.white.opacity(0.07)
    private static let usageLineColor = Color.white.opacity(0.3)
    private static let noDataFill = Color.white.opacity(0.06)

    private func xPosition(for timestamp: Date, windowStart: Date) -> Double {
        let elapsed = timestamp.timeIntervalSince(windowStart)
        return min(max(elapsed / windowSeconds, 0.0), 1.0)
    }

    private func usageValue(from point: UsageStore.DataPoint) -> Double? {
        if windowSeconds <= 5 * 3600 + 1 {
            return point.fiveHourPercent
        } else {
            return point.sevenDayPercent
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Background
            let bg = isLoggedIn ? Self.bgColor : Self.bgColorSignedOut
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            // Determine window start
            let windowStart: Date
            if let resetsAt {
                windowStart = resetsAt.addingTimeInterval(-windowSeconds)
            } else if let first = history.first {
                windowStart = first.timestamp
            } else {
                return
            }

            // Time division ticks
            for i in 1..<divisions {
                let x = CGFloat(i) / CGFloat(divisions) * w
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: 0))
                tickPath.addLine(to: CGPoint(x: x, y: h))
                context.stroke(tickPath, with: .color(Self.tickColor), lineWidth: 0.5)
            }

            // Build points (skip data before window start)
            var points: [(x: CGFloat, y: CGFloat)] = []
            for dp in history {
                guard dp.timestamp >= windowStart else { continue }
                guard let usage = usageValue(from: dp) else { continue }
                let xFrac = xPosition(for: dp.timestamp, windowStart: windowStart)
                let yFrac = min(usage / 100.0, 1.0)
                points.append((x: CGFloat(xFrac) * w, y: h - CGFloat(yFrac) * h))
            }

            guard !points.isEmpty else { return }

            // No-data gray fill: window start → first data point
            if points[0].x > 1 {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: points[0].x, height: h)),
                    with: .color(Self.noDataFill)
                )
            }

            // Current time position
            let now = Date()
            let nowElapsed = now.timeIntervalSince(windowStart)
            let nowXFrac = min(max(nowElapsed / windowSeconds, 0.0), 1.0)
            let nowX = CGFloat(nowXFrac) * w

            // Usage persists until reset — extend area to reset time
            let fillEndX: CGFloat
            if let resetsAt {
                let resetElapsed = resetsAt.timeIntervalSince(windowStart)
                let resetXFrac = min(max(resetElapsed / windowSeconds, 0.0), 1.0)
                let resetX = CGFloat(resetXFrac) * w
                fillEndX = max(resetX, points.last!.x)
            } else {
                fillEndX = max(nowX, points.last!.x)
            }

            // Area fill — past region (solid, up to nowX)
            let effectiveNowX = max(min(nowX, fillEndX), points.last!.x)
            var pastPath = Path()
            pastPath.move(to: CGPoint(x: points[0].x, y: h))
            for (i, p) in points.enumerated() {
                if i > 0 {
                    pastPath.addLine(to: CGPoint(x: p.x, y: points[i-1].y))
                }
                pastPath.addLine(to: CGPoint(x: p.x, y: p.y))
            }
            pastPath.addLine(to: CGPoint(x: effectiveNowX, y: points.last!.y))
            pastPath.addLine(to: CGPoint(x: effectiveNowX, y: h))
            pastPath.closeSubpath()
            context.fill(pastPath, with: .color(areaColor.opacity(areaOpacity)))

            // Area fill — future region (stripes + lower opacity, nowX to fillEndX)
            if fillEndX > effectiveNowX + 1 {
                let lastY = points.last!.y
                // Dimmed base fill
                var futurePath = Path()
                futurePath.addRect(CGRect(x: effectiveNowX, y: lastY, width: fillEndX - effectiveNowX, height: h - lastY))
                context.fill(futurePath, with: .color(areaColor.opacity(areaOpacity * 0.35)))
                // Diagonal stripes clipped to future area
                context.drawLayer { layerCtx in
                    layerCtx.clip(to: futurePath)
                    let spacing: CGFloat = 4
                    let totalSpan = (fillEndX - effectiveNowX) + (h - lastY)
                    var offset: CGFloat = -totalSpan
                    while offset < totalSpan {
                        var stripe = Path()
                        stripe.move(to: CGPoint(x: effectiveNowX + offset, y: lastY + (h - lastY)))
                        stripe.addLine(to: CGPoint(x: effectiveNowX + offset + (h - lastY), y: lastY))
                        layerCtx.stroke(stripe, with: .color(areaColor.opacity(areaOpacity * 0.5)), lineWidth: 0.5)
                        offset += spacing
                    }
                }
            }

            // Usage level: white dashed horizontal line
            let usageY = points.last!.y
            var usageLine = Path()
            usageLine.move(to: CGPoint(x: 0, y: usageY))
            usageLine.addLine(to: CGPoint(x: w, y: usageY))
            context.stroke(
                usageLine,
                with: .color(Self.usageLineColor),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
            )
        }
        .frame(width: chartWidth, height: 18)
    }
}
