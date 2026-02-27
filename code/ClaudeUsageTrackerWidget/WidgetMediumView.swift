// meta: created=2026-02-21 updated=2026-02-25 checked=never
import SwiftUI
import WidgetKit
import ClaudeUsageTrackerShared

struct WidgetMediumView: View {
    let snapshot: UsageSnapshot?

    private static let fiveHourColor = Color(red: 100/255, green: 180/255, blue: 255/255)
    private static let sevenDayColor = Color(red: 255/255, green: 130/255, blue: 180/255)

    var body: some View {
        if let snapshot {
            HStack(spacing: 8) {
                usageSection(
                    label: "5h",
                    percent: snapshot.fiveHourPercent,
                    resetsAt: snapshot.fiveHourResetsAt,
                    history: snapshot.fiveHourHistory,
                    windowSeconds: 5 * 3600,
                    color: Self.fiveHourColor,
                    opacity: 0.7
                )

                usageSection(
                    label: "7d",
                    percent: snapshot.sevenDayPercent,
                    resetsAt: snapshot.sevenDayResetsAt,
                    history: snapshot.sevenDayHistory,
                    windowSeconds: 7 * 24 * 3600,
                    color: Self.sevenDayColor,
                    opacity: 0.65
                )
            }
        } else {
            notFetchedView
        }
    }

    @ViewBuilder
    private func usageSection(
        label: String,
        percent: Double?,
        resetsAt: Date?,
        history: [HistoryPoint],
        windowSeconds: TimeInterval,
        color: Color,
        opacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetMiniGraph(
                label: label,
                history: history,
                windowSeconds: windowSeconds,
                resetsAt: resetsAt,
                areaColor: color,
                areaOpacity: opacity,
                isLoggedIn: snapshot?.isLoggedIn ?? true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let resetsAt {
                GeometryReader { geo in
                    let xFrac = nowXFraction(resetsAt: resetsAt, windowSeconds: windowSeconds)
                    Text(DisplayHelpers.remainingText(until: resetsAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: xFrac * geo.size.width, y: geo.size.height / 2)
                }
                .frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notFetchedView: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Not fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nowXFraction(resetsAt: Date, windowSeconds: TimeInterval) -> CGFloat {
        let windowStart = resetsAt.addingTimeInterval(-windowSeconds)
        let nowElapsed = Date().timeIntervalSince(windowStart)
        return CGFloat(min(max(nowElapsed / windowSeconds, 0.0), 1.0))
    }
}

// MARK: - Mini Graph for Widget

struct WidgetMiniGraph: View {
    let label: String
    let history: [HistoryPoint]
    let windowSeconds: TimeInterval
    let resetsAt: Date?
    let areaColor: Color
    let areaOpacity: Double
    let isLoggedIn: Bool

    private static let bgColor = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
    private static let bgColorSignedOut = Color(red: 0x3A/255, green: 0x10/255, blue: 0x10/255)
    private static let tickColor = Color.white.opacity(0.07)
    private static let usageLineColor = Color.white.opacity(0.3)
    private static let noDataFill = Color.white.opacity(0.06)

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Background
            let bg = isLoggedIn ? Self.bgColor : Self.bgColorSignedOut
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

            // Label (top-left)
            let labelText = context.resolve(
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            )
            context.draw(labelText, at: CGPoint(x: 4, y: 4), anchor: .topLeading)

            let windowStart: Date
            if let resetsAt {
                windowStart = resetsAt.addingTimeInterval(-windowSeconds)
            } else if let first = history.first {
                windowStart = first.timestamp
            } else {
                return
            }

            // Time division ticks
            let divisions = windowSeconds <= 5 * 3600 + 1 ? 5 : 7
            for i in 1..<divisions {
                let x = CGFloat(i) / CGFloat(divisions) * w
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: 0))
                tickPath.addLine(to: CGPoint(x: x, y: h))
                context.stroke(tickPath, with: .color(Self.tickColor), lineWidth: 0.5)
            }

            // Build points (skip data before window start)
            var points: [(x: CGFloat, y: CGFloat)] = []
            var lastPercent: Double = 0
            for dp in history {
                let elapsed = dp.timestamp.timeIntervalSince(windowStart)
                guard elapsed >= 0 else { continue }
                let xFrac = min(elapsed / windowSeconds, 1.0)
                let yFrac = min(dp.percent / 100.0, 1.0)
                points.append((x: CGFloat(xFrac) * w, y: h - CGFloat(yFrac) * h))
                lastPercent = dp.percent
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

            // Usage level line
            let usageY = points.last!.y
            var usageLine = Path()
            usageLine.move(to: CGPoint(x: 0, y: usageY))
            usageLine.addLine(to: CGPoint(x: w, y: usageY))
            context.stroke(
                usageLine,
                with: .color(Self.usageLineColor),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
            )

            // Current value marker (at current time)
            let markerX = nowX
            let markerY = points.last!.y

            // Filled inner circle (r = 2.5 * 2/3)
            var innerCircle = Path()
            innerCircle.addArc(center: CGPoint(x: markerX, y: markerY), radius: 2.5 * 2 / 3, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            context.fill(innerCircle, with: .color(.white))

            // Outer ring
            var outerCircle = Path()
            outerCircle.addArc(center: CGPoint(x: markerX, y: markerY), radius: 5, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            context.stroke(outerCircle, with: .color(.white.opacity(0.6)), lineWidth: 1)

            // Percent text (above or below marker)
            let percentText = context.resolve(
                Text(String(format: "%.0f%%", lastPercent))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            )
            let showBelow = DisplayHelpers.percentTextShowsBelow(markerY: markerY, graphHeight: h)
            let percentY = showBelow ? markerY + 14 : markerY - 10
            let percentAnchorX = DisplayHelpers.percentTextAnchorX(markerX: markerX, graphWidth: w)
            context.draw(percentText, at: CGPoint(x: markerX, y: percentY), anchor: UnitPoint(x: percentAnchorX, y: 0.5))
        }
    }
}
