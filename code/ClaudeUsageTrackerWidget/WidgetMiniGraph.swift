// meta: created=2026-02-21 updated=2026-03-04 checked=2026-03-03
import SwiftUI
import ClaudeUsageTrackerShared

struct WidgetMiniGraph: View {
    let label: String
    let history: [HistoryPoint]
    let windowSeconds: TimeInterval
    let resetsAt: Date?
    let areaColor: Color
    let areaOpacity: Double
    let isLoggedIn: Bool

    private enum Layout {
        static let bgColor = Color(red: 0x12/255, green: 0x12/255, blue: 0x12/255)
        static let bgColorSignedOut = Color(red: 0x3A/255, green: 0x10/255, blue: 0x10/255)
        static let tickColor = Color.white.opacity(0.07)
        static let usageLineColor = Color.white.opacity(0.3)
        static let noDataFill = Color.white.opacity(0.06)
        static let labelFontSize: CGFloat = 9
        static let labelOrigin = CGPoint(x: 4, y: 4)
        static let labelOpacity: Double = 0.5
        static let tickLineWidth: CGFloat = 0.5
        static let usageDash: [CGFloat] = [2, 2]
        static let usageLineWidth: CGFloat = 0.5
        static let markerInnerRadius: CGFloat = 2.5 * 2 / 3
        static let markerOuterRadius: CGFloat = 5
        static let markerRingWidth: CGFloat = 1
        static let markerRingOpacity: Double = 0.6
        static let percentFontSize: CGFloat = 9
        static let percentOpacity: Double = 0.8
        static let percentBelowOffset: CGFloat = 14
        static let percentAboveOffset: CGFloat = 10
        static let futureOpacityMultiplier: Double = 0.35
        static let stripeSpacing: CGFloat = 4
        static let stripeOpacityMultiplier: Double = 0.5
        static let stripeLineWidth: CGFloat = 0.5
        static let fiveHourWindowThreshold: TimeInterval = 5 * 3600 + 1
    }

    private struct GraphPoints {
        let points: [(x: CGFloat, y: CGFloat)]
        let lastPercent: Double
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            drawBackground(&context, size: size)
            drawLabel(&context)

            guard let windowStart = resolveWindowStart() else { return }

            drawTicks(&context, w: w, h: h)

            guard let graph = buildPoints(windowStart: windowStart, w: w, h: h) else { return }
            let points = graph.points
            let lastPercent = graph.lastPercent

            drawNoDataRegion(&context, firstX: points[0].x, h: h)

            let nowX = nowXPosition(windowStart: windowStart, w: w)
            let fillEndX = computeFillEndX(windowStart: windowStart, w: w, nowX: nowX, lastPointX: points.last!.x)
            let effectiveNowX = max(min(nowX, fillEndX), points.last!.x)

            drawPastArea(&context, points: points, effectiveNowX: effectiveNowX, h: h)
            drawFutureStripes(&context, effectiveNowX: effectiveNowX, fillEndX: fillEndX, lastY: points.last!.y, h: h)
            drawUsageLine(&context, y: points.last!.y, w: w)
            drawMarker(&context, x: nowX, y: points.last!.y)
            drawPercentText(&context, markerX: nowX, markerY: points.last!.y, lastPercent: lastPercent, h: h, w: w)
        }
    }

    // MARK: - Drawing Phases

    private func drawBackground(_ context: inout GraphicsContext, size: CGSize) {
        let bg = isLoggedIn ? Layout.bgColor : Layout.bgColorSignedOut
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
    }

    private func drawLabel(_ context: inout GraphicsContext) {
        let labelText = context.resolve(
            Text(label)
                .font(.system(size: Layout.labelFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(Layout.labelOpacity))
        )
        context.draw(labelText, at: Layout.labelOrigin, anchor: .topLeading)
    }

    private func resolveWindowStart() -> Date? {
        if let resetsAt {
            return resetsAt.addingTimeInterval(-windowSeconds)
        } else if let first = history.first {
            return first.timestamp
        }
        return nil
    }

    private func drawTicks(_ context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let divisions = windowSeconds <= Layout.fiveHourWindowThreshold ? 5 : 7
        for i in 1..<divisions {
            let x = CGFloat(i) / CGFloat(divisions) * w
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: 0))
            tickPath.addLine(to: CGPoint(x: x, y: h))
            context.stroke(tickPath, with: .color(Layout.tickColor), lineWidth: Layout.tickLineWidth)
        }
    }

    private func buildPoints(windowStart: Date, w: CGFloat, h: CGFloat) -> GraphPoints? {
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
        guard !points.isEmpty else { return nil }
        return GraphPoints(points: points, lastPercent: lastPercent)
    }

    private func drawNoDataRegion(_ context: inout GraphicsContext, firstX: CGFloat, h: CGFloat) {
        if firstX > 1 {
            context.fill(
                Path(CGRect(x: 0, y: 0, width: firstX, height: h)),
                with: .color(Layout.noDataFill)
            )
        }
    }

    private func nowXPosition(windowStart: Date, w: CGFloat) -> CGFloat {
        let nowElapsed = Date().timeIntervalSince(windowStart)
        let nowXFrac = min(max(nowElapsed / windowSeconds, 0.0), 1.0)
        return CGFloat(nowXFrac) * w
    }

    private func computeFillEndX(windowStart: Date, w: CGFloat, nowX: CGFloat, lastPointX: CGFloat) -> CGFloat {
        if let resetsAt {
            let resetElapsed = resetsAt.timeIntervalSince(windowStart)
            let resetXFrac = min(max(resetElapsed / windowSeconds, 0.0), 1.0)
            let resetX = CGFloat(resetXFrac) * w
            return max(resetX, lastPointX)
        } else {
            return max(nowX, lastPointX)
        }
    }

    private func drawPastArea(_ context: inout GraphicsContext, points: [(x: CGFloat, y: CGFloat)], effectiveNowX: CGFloat, h: CGFloat) {
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
    }

    private func drawFutureStripes(_ context: inout GraphicsContext, effectiveNowX: CGFloat, fillEndX: CGFloat, lastY: CGFloat, h: CGFloat) {
        guard fillEndX > effectiveNowX + 1 else { return }
        var futurePath = Path()
        futurePath.addRect(CGRect(x: effectiveNowX, y: lastY, width: fillEndX - effectiveNowX, height: h - lastY))
        context.fill(futurePath, with: .color(areaColor.opacity(areaOpacity * Layout.futureOpacityMultiplier)))
        context.drawLayer { layerCtx in
            layerCtx.clip(to: futurePath)
            let totalSpan = (fillEndX - effectiveNowX) + (h - lastY)
            var offset: CGFloat = -totalSpan
            while offset < totalSpan {
                var stripe = Path()
                stripe.move(to: CGPoint(x: effectiveNowX + offset, y: lastY + (h - lastY)))
                stripe.addLine(to: CGPoint(x: effectiveNowX + offset + (h - lastY), y: lastY))
                layerCtx.stroke(stripe, with: .color(areaColor.opacity(areaOpacity * Layout.stripeOpacityMultiplier)), lineWidth: Layout.stripeLineWidth)
                offset += Layout.stripeSpacing
            }
        }
    }

    private func drawUsageLine(_ context: inout GraphicsContext, y: CGFloat, w: CGFloat) {
        var usageLine = Path()
        usageLine.move(to: CGPoint(x: 0, y: y))
        usageLine.addLine(to: CGPoint(x: w, y: y))
        context.stroke(
            usageLine,
            with: .color(Layout.usageLineColor),
            style: StrokeStyle(lineWidth: Layout.usageLineWidth, dash: Layout.usageDash)
        )
    }

    private func drawMarker(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        var innerCircle = Path()
        innerCircle.addArc(center: CGPoint(x: x, y: y), radius: Layout.markerInnerRadius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        context.fill(innerCircle, with: .color(.white))

        var outerCircle = Path()
        outerCircle.addArc(center: CGPoint(x: x, y: y), radius: Layout.markerOuterRadius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        context.stroke(outerCircle, with: .color(.white.opacity(Layout.markerRingOpacity)), lineWidth: Layout.markerRingWidth)
    }

    private func drawPercentText(_ context: inout GraphicsContext, markerX: CGFloat, markerY: CGFloat, lastPercent: Double, h: CGFloat, w: CGFloat) {
        let percentText = context.resolve(
            Text(String(format: "%.0f%%", lastPercent))
                .font(.system(size: Layout.percentFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(Layout.percentOpacity))
        )
        let showBelow = DisplayHelpers.percentTextShowsBelow(percent: lastPercent)
        let percentY = showBelow ? markerY + Layout.percentBelowOffset : markerY - Layout.percentAboveOffset
        let percentAnchorX = DisplayHelpers.percentTextAnchorX(markerX: markerX, graphWidth: w)
        context.draw(percentText, at: CGPoint(x: markerX, y: percentY), anchor: UnitPoint(x: percentAnchorX, y: 0.5))
    }
}
